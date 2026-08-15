require "test_helper"

module Api
  class SellerOrdersTest < ActionDispatch::IntegrationTest
    self.fixture_table_names = []

    test "returns distinct seller orders with seller-only aggregates and external products" do
      seller = create_seller(seller_id: "requested-seller-id")
      other_seller = create_seller(seller_id: "other-seller-id")
      order = create_order(order_id: "shared-order-id")
      repeated_product = create_product(product_id: "repeated-product-id", category_name: "moveis_decoracao")
      second_product = create_product(product_id: "second-product-id", category_name: nil)
      other_product = create_product(product_id: "other-product-id", category_name: "telefonia")

      create_item(
        order: order,
        product: repeated_product,
        seller: seller,
        order_item_id: 1,
        price: "9.90",
        freight_value: "1.02"
      )
      create_item(
        order: order,
        product: repeated_product,
        seller: seller,
        order_item_id: 2,
        price: "20.00",
        freight_value: "0.08"
      )
      create_item(
        order: order,
        product: second_product,
        seller: seller,
        order_item_id: 3,
        price: "0.01",
        freight_value: "0.00"
      )
      create_item(
        order: order,
        product: other_product,
        seller: other_seller,
        order_item_id: 4,
        price: "999.00",
        freight_value: "99.00"
      )

      get "/api/sellers/#{seller.seller_id}/orders"

      assert_response :ok
      assert_equal "application/json", response.media_type

      body = response.parsed_body
      assert_equal %w[orders page per_page seller_id total_orders], body.keys.sort
      assert_equal "requested-seller-id", body["seller_id"]
      assert_equal 1, body["page"]
      assert_equal 20, body["per_page"]
      assert_equal 1, body["total_orders"]
      assert_equal 1, body.fetch("orders").size

      returned_order = body.fetch("orders").first
      assert_equal %w[
        freight_value item_count items_value order_id products purchase_at status total_value
      ], returned_order.keys.sort
      assert_equal "shared-order-id", returned_order["order_id"]
      assert_equal "delivered", returned_order["status"]
      assert_equal "2017-10-02T10:56:33.000Z", returned_order["purchase_at"]
      assert_equal 3, returned_order["item_count"]
      assert_equal "29.91", returned_order["items_value"]
      assert_equal "1.10", returned_order["freight_value"]
      assert_equal "31.01", returned_order["total_value"]
      assert_equal(
        [
          { "product_id" => "repeated-product-id", "category_name" => "moveis_decoracao" },
          { "product_id" => "second-product-id", "category_name" => nil }
        ],
        returned_order["products"]
      )

      assert_no_internal_ids(body)
    end

    test "orders deterministically paginate by purchase time then external order id" do
      seller = create_seller
      product = create_product
      older = create_order(order_id: "order-0", purchase_at: Time.utc(2017, 9, 30))
      tied_b = create_order(order_id: "order-b", purchase_at: Time.utc(2017, 10, 2))
      tied_a = create_order(order_id: "order-a", purchase_at: Time.utc(2017, 10, 2))

      [ older, tied_b, tied_a ].each_with_index do |order, index|
        create_item(order: order, product: product, seller: seller, order_item_id: index + 1)
      end

      get "/api/sellers/#{seller.seller_id}/orders"

      assert_response :ok
      assert_equal 1, response.parsed_body["page"]
      assert_equal 20, response.parsed_body["per_page"]
      assert_equal %w[order-a order-b order-0], response.parsed_body.fetch("orders").pluck("order_id")

      get "/api/sellers/#{seller.seller_id}/orders", params: { page: 1, per_page: 2 }
      first_page = response.parsed_body
      get "/api/sellers/#{seller.seller_id}/orders", params: { page: 2, per_page: 2 }
      second_page = response.parsed_body

      assert_equal %w[order-a order-b], first_page.fetch("orders").pluck("order_id")
      assert_equal [ "order-0" ], second_page.fetch("orders").pluck("order_id")
      assert_equal 3, second_page["total_orders"]
    end

    test "accepts the maximum page size and safely returns an empty out-of-range page" do
      seller = create_seller
      order = create_order
      create_item(order: order, product: create_product, seller: seller)

      get "/api/sellers/#{seller.seller_id}/orders", params: { page: 2, per_page: 100 }

      assert_response :ok
      assert_equal 2, response.parsed_body["page"]
      assert_equal 100, response.parsed_body["per_page"]
      assert_equal 1, response.parsed_body["total_orders"]
      assert_equal [], response.parsed_body["orders"]
    end

    test "rejects malformed pagination before querying for the seller" do
      invalid_parameters = [
        { page: "0" },
        { page: "-1" },
        { page: "abc" },
        { page: "1.5" },
        { page: " 1" },
        { page: [ "1" ] },
        { per_page: "0" },
        { per_page: "-10" },
        { per_page: "101" },
        { per_page: "abc" },
        { per_page: [ "20" ] }
      ]

      invalid_parameters.each do |parameters|
        select_count = capture_select_count do
          get "/api/sellers/unknown-seller/orders", params: parameters
        end

        assert_equal 422, response.status, "expected #{parameters.inspect} to be rejected"
        assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
        assert_equal 0, select_count, "invalid pagination should be rejected before database access"
      end
    end

    test "returns the exact not-found contract for an unknown external seller id" do
      get "/api/sellers/unknown-external-seller/orders"

      assert_response :not_found
      assert_equal "application/json", response.media_type
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
      assert_equal [ "error" ], response.parsed_body.keys
    end

    test "select query count remains constant as the requested page size grows" do
      seller = create_seller
      product = create_product

      50.times do |index|
        order = create_order(
          order_id: format("performance-order-%02d", index),
          purchase_at: Time.utc(2017, 10, 2) - index.minutes
        )
        create_item(order: order, product: product, seller: seller)
      end

      small_page_selects = capture_select_count do
        get "/api/sellers/#{seller.seller_id}/orders", params: { page: 1, per_page: 5 }
        assert_response :ok
        assert_equal 5, response.parsed_body.fetch("orders").size
      end
      large_page_selects = capture_select_count do
        get "/api/sellers/#{seller.seller_id}/orders", params: { page: 1, per_page: 50 }
        assert_response :ok
        assert_equal 50, response.parsed_body.fetch("orders").size
      end

      assert_operator small_page_selects, :<=, 6, "small page executed implausibly many SELECTs"
      assert_operator large_page_selects, :<=, 6, "large page executed implausibly many SELECTs"
      assert_operator(
        (small_page_selects - large_page_selects).abs,
        :<=,
        1,
        "SELECT count should not grow with returned order count " \
          "(per_page=5: #{small_page_selects}, per_page=50: #{large_page_selects})"
      )
    end

    private

    def assert_no_internal_ids(value)
      case value
      when Hash
        refute_includes value.keys, "id"
        refute value.keys.any? { |key| key.start_with?("internal_") }
        value.each_value { |nested_value| assert_no_internal_ids(nested_value) }
      when Array
        value.each { |nested_value| assert_no_internal_ids(nested_value) }
      end
    end

    def capture_select_count
      ActiveRecord::Base.connection.clear_query_cache
      count = 0
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]
        next unless payload[:sql].match?(/\ASELECT\b/i)

        count += 1
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
      count
    end

    def create_customer
      sequence = SecureRandom.hex(8)
      Customer.create!(
        customer_id: "customer-#{sequence}",
        customer_unique_id: "unique-#{sequence}",
        zip_code_prefix: "01001",
        city: "curitiba",
        state: "PR"
      )
    end

    def create_order(order_id: "default-order-id", purchase_at: Time.utc(2017, 10, 2, 10, 56, 33))
      Order.create!(
        customer: create_customer,
        order_id: order_id,
        status: "delivered",
        purchase_at: purchase_at,
        approved_at: Time.utc(2017, 10, 2, 11, 7, 15),
        delivered_carrier_at: Time.utc(2017, 10, 4, 19, 55),
        delivered_customer_at: Time.utc(2017, 10, 10, 21, 25, 13),
        estimated_delivery_at: Time.utc(2017, 10, 18)
      )
    end

    def create_product(product_id: "default-product-id", category_name: "informatica_acessorios")
      Product.create!(product_id: product_id, category_name: category_name)
    end

    def create_seller(seller_id: "default-seller-id")
      Seller.create!(
        seller_id: seller_id,
        zip_code_prefix: "01001",
        city: "sao paulo",
        state: "SP"
      )
    end

    def create_item(order:, product:, seller:, order_item_id: 1, price: "10.00", freight_value: "1.00")
      OrderItem.create!(
        order: order,
        product: product,
        seller: seller,
        order_item_id: order_item_id,
        price: price,
        freight_value: freight_value,
        shipping_limit_at: Time.utc(2017, 10, 6)
      )
    end
  end
end
