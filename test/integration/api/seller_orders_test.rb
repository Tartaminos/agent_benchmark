require "test_helper"

module Api
  class SellerOrdersTest < ActionDispatch::IntegrationTest
    self.fixture_table_names = []

    setup do
      @customer = Customer.create!(
        customer_id: "customer-seller-orders-01",
        customer_unique_id: "shopper-seller-orders-01",
        zip_code_prefix: "01001",
        city: "sao paulo",
        state: "SP"
      )
      @seller = create_seller("seller-orders-target-01")
      @other_seller = create_seller("seller-orders-other-01")
      @product_a = create_product("product-seller-orders-a", "moveis_decoracao")
      @product_b = create_product("product-seller-orders-b", nil)
    end

    test "returns the exact seller-specific contract with distinct orders and products" do
      order = create_order(
        "order-seller-contract-01",
        purchase_at: Time.utc(2024, 1, 2, 3, 4, 5),
        status: "delivered"
      )
      create_item(order:, seller: @seller, product: @product_a, position: 1, price: "10.10", freight: "1.20")
      create_item(order:, seller: @seller, product: @product_a, position: 2, price: "0.20", freight: "0.30")
      create_item(order:, seller: @seller, product: @product_b, position: 3, price: "2.00", freight: "0.40")
      create_item(order:, seller: @other_seller, product: @product_b, position: 4, price: "999.99", freight: "99.99")

      get seller_orders_path(@seller)

      assert_response :ok
      assert_equal(
        {
          "seller_id" => "seller-orders-target-01",
          "page" => 1,
          "per_page" => 20,
          "total_orders" => 1,
          "orders" => [
            {
              "order_id" => "order-seller-contract-01",
              "status" => "delivered",
              "purchase_at" => "2024-01-02T03:04:05.000Z",
              "item_count" => 3,
              "items_value" => "12.30",
              "freight_value" => "1.90",
              "total_value" => "14.20",
              "products" => [
                { "product_id" => "product-seller-orders-a", "category_name" => "moveis_decoracao" },
                { "product_id" => "product-seller-orders-b", "category_name" => nil }
              ]
            }
          ]
        },
        response.parsed_body
      )
    end

    test "orders equal purchase times by external id and slices pages deterministically" do
      %w[c a b].each do |suffix|
        order = create_order("order-tie-#{suffix}", purchase_at: Time.utc(2024, 6, 1, 12))
        create_item(order:, seller: @seller, product: @product_a, position: 1, price: "1.00", freight: "0.00")
      end

      get seller_orders_path(@seller), params: { page: "1", per_page: "2" }

      assert_response :ok
      assert_equal %w[order-tie-a order-tie-b], response.parsed_body.fetch("orders").pluck("order_id")
      assert_equal 3, response.parsed_body["total_orders"]

      get seller_orders_path(@seller), params: { page: "2", per_page: "2" }

      assert_response :ok
      assert_equal %w[order-tie-c], response.parsed_body.fetch("orders").pluck("order_id")
      assert_equal({ "page" => 2, "per_page" => 2 }, response.parsed_body.slice("page", "per_page"))
    end

    test "accepts pagination bounds and returns an empty valid far page" do
      order = create_order("order-pagination-bound-01", purchase_at: Time.utc(2024, 1, 1))
      create_item(order:, seller: @seller, product: @product_a, position: 1, price: "1.00", freight: "0.00")

      get seller_orders_path(@seller), params: { page: "1", per_page: "100" }

      assert_response :ok
      assert_equal({ "page" => 1, "per_page" => 100 }, response.parsed_body.slice("page", "per_page"))
      assert_equal 1, response.parsed_body["total_orders"]

      get seller_orders_path(@seller), params: { page: "999999999999999999999999999999999", per_page: "1" }

      assert_response :ok
      assert_equal [], response.parsed_body["orders"]
      assert_equal 1, response.parsed_body["total_orders"]
    end

    test "rejects non-canonical, non-positive, excessive, and structured pagination values" do
      invalid_queries = [
        "page=0", "page=-1", "page=abc", "page=1.0", "page=01", "page=%2B1", "page=%201", "page=",
        "per_page=0", "per_page=-10", "per_page=abc", "per_page=1.0", "per_page=01", "per_page=101", "per_page[]=1"
      ]

      invalid_queries.each do |query|
        get "#{seller_orders_path(@seller)}?#{query}"

        assert_response :unprocessable_entity, "expected #{query.inspect} to be rejected"
        assert_equal({ "error" => "invalid_pagination" }, response.parsed_body, "wrong response for #{query.inspect}")
      end
    end

    test "returns the exact not found response for an unknown external seller id" do
      get seller_orders_path("seller-orders-missing-01")

      assert_response :not_found
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
    end

    test "SELECT count stays constant when the requested page grows from 5 to 50 orders" do
      50.times do |index|
        order = create_order(
          format("order-performance-%02d", index),
          purchase_at: Time.utc(2024, 7, 1) + index.seconds
        )
        create_item(order:, seller: @seller, product: @product_a, position: 1, price: "1.00", freight: "0.10")
      end

      get seller_orders_path(@seller), params: { page: "1", per_page: "1" }
      assert_response :ok

      five_order_selects = count_uncached_selects do
        get seller_orders_path(@seller), params: { page: "1", per_page: "5" }
        assert_response :ok
        assert_equal 5, response.parsed_body.fetch("orders").length
      end
      fifty_order_selects = count_uncached_selects do
        get seller_orders_path(@seller), params: { page: "1", per_page: "50" }
        assert_response :ok
        assert_equal 50, response.parsed_body.fetch("orders").length
      end

      assert_operator five_order_selects, :<=, 5
      assert_operator fifty_order_selects, :<=, 5
      assert_operator (fifty_order_selects - five_order_selects).abs, :<=, 1
    end

    private

    def seller_orders_path(seller)
      seller_id = seller.respond_to?(:seller_id) ? seller.seller_id : seller
      "/api/sellers/#{seller_id}/orders"
    end

    def create_seller(seller_id)
      Seller.create!(
        seller_id:,
        zip_code_prefix: "20001",
        city: "rio de janeiro",
        state: "RJ"
      )
    end

    def create_product(product_id, category_name)
      Product.create!(product_id:, category_name:)
    end

    def create_order(order_id, purchase_at:, status: "processing")
      Order.create!(
        order_id:,
        customer: @customer,
        status:,
        purchase_at:,
        estimated_delivery_at: purchase_at + 7.days
      )
    end

    def create_item(order:, seller:, product:, position:, price:, freight:)
      OrderItem.create!(
        order:,
        seller:,
        product:,
        order_item_id: position,
        shipping_limit_at: order.purchase_at + 1.day,
        price:,
        freight_value: freight
      )
    end

    def count_uncached_selects
      count = 0
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        sql = payload[:sql].to_s.lstrip
        count += 1 if !payload[:cached] && payload[:name] != "SCHEMA" && sql.match?(/\ASELECT\b/i)
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
      count
    end
  end
end
