require "test_helper"

class Api::SellerOrdersTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @customer = Customer.create!(
      customer_id: "seller_orders_customer",
      customer_unique_id: "seller_orders_unique",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @seller = create_seller("seller_orders_external")
    @other_seller = create_seller("seller_orders_other")
    @first_product = Product.create!(product_id: "seller_product_first", category_name: "casa")
    @second_product = Product.create!(product_id: "seller_product_second", category_name: "livros")

    @latest_order = create_order("seller_order_c", Time.utc(2018, 3, 1, 12))
    @first_tied_order = create_order("seller_order_a", Time.utc(2018, 2, 1, 12))
    @second_tied_order = create_order("seller_order_b", Time.utc(2018, 2, 1, 12))

    create_item(@latest_order, @seller, @first_product, 1, "10.10", "0.05")
    create_item(@latest_order, @seller, @first_product, 2, "1.20", "0.15")
    create_item(@latest_order, @seller, @second_product, 3, "2.00", "3.40")
    create_item(@latest_order, @other_seller, @second_product, 4, "999.99", "99.99")
    create_item(@first_tied_order, @seller, @first_product, 1, "4.00", "1.00")
    create_item(@second_tied_order, @seller, @second_product, 1, "0.00", "0.00")
  end

  test "index returns the exact seller-scoped contract with defaults and distinct products" do
    sql = capture_request_sql do
      get "/api/sellers/#{@seller.seller_id}/orders"
    end

    assert_response :success
    assert_equal "application/json", response.media_type
    assert sql.all? { |statement| statement.match?(/\ASELECT\b/i) },
           "expected a read-only endpoint, got: #{sql.join("\n\n")}"

    assert_equal(
      {
        "seller_id" => "seller_orders_external",
        "page" => 1,
        "per_page" => 20,
        "total_orders" => 3,
        "orders" => [
          {
            "order_id" => "seller_order_c",
            "status" => "delivered",
            "purchase_at" => "2018-03-01T12:00:00.000Z",
            "item_count" => 3,
            "items_value" => "13.30",
            "freight_value" => "3.60",
            "total_value" => "16.90",
            "products" => [
              { "product_id" => "seller_product_first", "category_name" => "casa" },
              { "product_id" => "seller_product_second", "category_name" => "livros" }
            ]
          },
          {
            "order_id" => "seller_order_a",
            "status" => "delivered",
            "purchase_at" => "2018-02-01T12:00:00.000Z",
            "item_count" => 1,
            "items_value" => "4.00",
            "freight_value" => "1.00",
            "total_value" => "5.00",
            "products" => [
              { "product_id" => "seller_product_first", "category_name" => "casa" }
            ]
          },
          {
            "order_id" => "seller_order_b",
            "status" => "delivered",
            "purchase_at" => "2018-02-01T12:00:00.000Z",
            "item_count" => 1,
            "items_value" => "0.00",
            "freight_value" => "0.00",
            "total_value" => "0.00",
            "products" => [
              { "product_id" => "seller_product_second", "category_name" => "livros" }
            ]
          }
        ]
      },
      response.parsed_body
    )
  end

  test "index paginates deterministic purchase-time ties and accepts the maximum page size" do
    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: "2", per_page: "1" }

    assert_response :success
    assert_equal 2, response.parsed_body.fetch("page")
    assert_equal 1, response.parsed_body.fetch("per_page")
    assert_equal 3, response.parsed_body.fetch("total_orders")
    assert_equal [ "seller_order_a" ], response.parsed_body.fetch("orders").pluck("order_id")

    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: "1", per_page: "100" }

    assert_response :success
    assert_equal 100, response.parsed_body.fetch("per_page")
    assert_equal %w[seller_order_c seller_order_a seller_order_b],
                 response.parsed_body.fetch("orders").pluck("order_id")
  end

  test "index treats an arbitrarily large positive page as valid without overflowing the database offset" do
    huge_page = "999999999999999999999999999999999999999999999999999999999999"

    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: huge_page, per_page: "7" }

    assert_response :success
    assert_equal(
      {
        "seller_id" => "seller_orders_external",
        "page" => huge_page.to_i,
        "per_page" => 7,
        "total_orders" => 3,
        "orders" => []
      },
      response.parsed_body
    )
  end

  test "index strictly rejects scalar and structured invalid pagination before seller lookup" do
    invalid_params = [
      { page: "0" },
      { page: "-1" },
      { page: "abc" },
      { page: "01" },
      { page: "+1" },
      { page: [] },
      { page: { nested: "1" } },
      { per_page: "0" },
      { per_page: "-10" },
      { per_page: "101" },
      { per_page: "abc" },
      { per_page: [] },
      { per_page: { nested: "20" } }
    ]

    invalid_params.each do |params|
      get "/api/sellers/unknown-seller/orders", params: params

      assert_response :unprocessable_content, "expected #{params.inspect} to be rejected"
      assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
    end
  end

  test "index returns the exact not found response and does not accept an internal seller id" do
    [ "does-not-exist", @seller.id.to_s ].each do |seller_id|
      get "/api/sellers/#{seller_id}/orders"

      assert_response :not_found
      assert_equal "application/json", response.media_type
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
    end
  end

  test "index keeps SELECT count effectively constant as the requested page grows" do
    performance_seller = create_seller("seller_orders_performance")
    product = Product.create!(product_id: "seller_performance_product", category_name: "office")
    50.times do |number|
      order = create_order(format("performance_order_%02d", number), Time.utc(2019, 1, 1) + number.hours)
      create_item(order, performance_seller, product, 1, "1.00", "0.10")
    end

    five_sql = capture_request_sql do
      get "/api/sellers/#{performance_seller.seller_id}/orders", params: { page: "1", per_page: "5" }
    end
    assert_response :success
    five_order_count = response.parsed_body.fetch("orders").size

    fifty_sql = capture_request_sql do
      get "/api/sellers/#{performance_seller.seller_id}/orders", params: { page: "1", per_page: "50" }
    end
    assert_response :success

    assert_equal 5, five_order_count
    assert_equal 50, response.parsed_body.fetch("orders").size
    assert_operator (five_sql.size - fifty_sql.size).abs, :<=, 1,
                    "expected bounded SELECT growth; per_page=5: #{five_sql.inspect}, " \
                    "per_page=50: #{fifty_sql.inspect}"
    assert (five_sql + fifty_sql).all? { |statement| statement.match?(/\ASELECT\b/i) },
           "expected only read-only SQL during measured requests"
  end

  private

  def create_seller(external_id)
    Seller.create!(
      seller_id: external_id,
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  def create_order(external_id, purchase_at)
    Order.create!(
      order_id: external_id,
      customer: @customer,
      status: "delivered",
      purchase_at: purchase_at,
      estimated_delivery_at: purchase_at + 7.days
    )
  end

  def create_item(order, seller, product, item_number, price, freight)
    OrderItem.create!(
      order: order,
      seller: seller,
      product: product,
      order_item_id: item_number,
      shipping_limit_at: order.purchase_at + 1.day,
      price: price,
      freight_value: freight
    )
  end

  def capture_request_sql
    counter = ActiveRecord::Assertions::QueryAssertions::SQLCounter.new
    ActiveRecord::Base.lease_connection.materialize_transactions
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    end
    counter.log
  end
end
