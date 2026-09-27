require "test_helper"

class Api::SellerOrdersControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @customer = Customer.create!(
      customer_id: "sellerorderscustomer00000000001",
      customer_unique_id: "sellerordersunique000000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @seller = Seller.create!(
      seller_id: "publicseller00000000000000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @other_seller = Seller.create!(
      seller_id: "otherseller0000000000000000001",
      zip_code_prefix: "20001",
      city: "rio de janeiro",
      state: "RJ"
    )
    @product_one = Product.create!(product_id: "sellerproduct0000000000000000001", category_name: "category_one")
    @product_two = Product.create!(product_id: "sellerproduct0000000000000000002", category_name: nil)
    @other_product = Product.create!(product_id: "otherproduct00000000000000000001", category_name: "other_category")
  end

  test "returns exact seller order contract with seller-only aggregates and distinct products" do
    order = create_order("sellerorder000000000000000000001", "2018-01-02 03:04:05 UTC")
    create_item(order, @seller, @product_one, 1, "10.10", "1.01")
    create_item(order, @seller, @product_one, 2, "20.20", "2.02")
    create_item(order, @seller, @product_two, 3, "0.03", "0.04")
    create_item(order, @other_seller, @other_product, 4, "999.99", "88.88")

    get "/api/sellers/#{@seller.seller_id}/orders"

    assert_response :success
    assert_equal(
      {
        "seller_id" => @seller.seller_id,
        "page" => 1,
        "per_page" => 20,
        "total_orders" => 1,
        "orders" => [
          {
            "order_id" => order.order_id,
            "status" => "delivered",
            "purchase_at" => "2018-01-02T03:04:05.000Z",
            "item_count" => 3,
            "items_value" => "30.33",
            "freight_value" => "3.07",
            "total_value" => "33.40",
            "products" => [
              { "product_id" => @product_one.product_id, "category_name" => "category_one" },
              { "product_id" => @product_two.product_id, "category_name" => nil }
            ]
          }
        ]
      },
      response.parsed_body
    )
    refute_includes response.body, order.id.to_s
    refute_includes response.body, @seller.id.to_s
    refute_includes response.body, @product_one.id.to_s
  end

  test "orders are distinct and paginate by purchase time then external order id" do
    older = create_order("sellerorder000000000000000000003", "2018-01-01 00:00:00 UTC")
    tied_second = create_order("sellerorder000000000000000000002", "2018-01-02 00:00:00 UTC")
    tied_first = create_order("sellerorder000000000000000000001", "2018-01-02 00:00:00 UTC")
    [older, tied_second, tied_first].each_with_index do |order, index|
      create_item(order, @seller, @product_one, 1, index + 1, "0.00")
      create_item(order, @seller, @product_two, 2, index + 1, "0.00")
    end

    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: 1, per_page: 2 }

    assert_response :success
    assert_equal 3, response.parsed_body["total_orders"]
    assert_equal [tied_first.order_id, tied_second.order_id], response.parsed_body["orders"].map { |value| value["order_id"] }

    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: 2, per_page: 2 }

    assert_response :success
    assert_equal [older.order_id], response.parsed_body["orders"].map { |value| value["order_id"] }

    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: 3, per_page: 2 }

    assert_response :success
    assert_equal 3, response.parsed_body["total_orders"]
    assert_equal [], response.parsed_body["orders"]
  end

  test "existing seller without orders gets a successful empty result" do
    get "/api/sellers/#{@seller.seller_id}/orders"

    assert_response :success
    assert_equal(
      { "seller_id" => @seller.seller_id, "page" => 1, "per_page" => 20, "total_orders" => 0, "orders" => [] },
      response.parsed_body
    )
  end

  test "rejects every invalid pagination class with the exact response" do
    invalid_parameters = [
      { page: "0" },
      { page: "-1" },
      { page: "abc" },
      { page: "1.0" },
      { page: "+1" },
      { page: " 1" },
      { page: "" },
      { per_page: "0" },
      { per_page: "-10" },
      { per_page: "101" },
      { per_page: "abc" },
      { per_page: "20.0" },
      { per_page: "+20" },
      { per_page: " 20" },
      { per_page: "" }
    ]

    invalid_parameters.each do |parameters|
      get "/api/sellers/#{@seller.seller_id}/orders", params: parameters
      assert_response :unprocessable_content, "expected #{parameters.inspect} to be rejected"
      assert_equal({ "error" => "invalid_pagination" }, response.parsed_body, "wrong response for #{parameters.inspect}")
    end
  end

  test "accepts pagination boundaries and reports requested values" do
    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: 1, per_page: 100 }

    assert_response :success
    assert_equal 1, response.parsed_body["page"]
    assert_equal 100, response.parsed_body["per_page"]
  end

  test "returns exact not found response and never treats an internal id as public" do
    get "/api/sellers/unknown-seller/orders"
    assert_response :not_found
    assert_equal({ "error" => "seller_not_found" }, response.parsed_body)

    get "/api/sellers/#{@seller.id}/orders"
    assert_response :not_found
    assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
  end

  test "select count stays constant as returned order count grows" do
    52.times do |index|
      order = create_order(format("perf%028d", index), Time.utc(2018, 1, 1) + index.seconds)
      create_item(order, @seller, index.even? ? @product_one : @product_two, 1, "1.00", "0.10")
    end

    small_count = select_count_for("/api/sellers/#{@seller.seller_id}/orders?page=1&per_page=5")
    assert_response :success
    large_count = select_count_for("/api/sellers/#{@seller.seller_id}/orders?page=1&per_page=50")
    assert_response :success

    assert_operator (small_count - large_count).abs, :<=, 1,
      "SELECT count grew with page size: per_page=5 used #{small_count}, per_page=50 used #{large_count}"
    assert_operator large_count, :<=, 6,
      "expected a bounded query plan, got #{large_count} SELECTs for 50 orders"
  end

  private

  def create_order(external_id, purchased_at)
    Order.create!(
      order_id: external_id,
      customer: @customer,
      status: "delivered",
      purchase_at: purchased_at,
      estimated_delivery_at: Time.utc(2018, 2, 1)
    )
  end

  def create_item(order, seller, product, sequence, price, freight)
    OrderItem.create!(
      order: order,
      seller: seller,
      product: product,
      order_item_id: sequence,
      shipping_limit_at: Time.utc(2018, 1, 10),
      price: price,
      freight_value: freight
    )
  end

  def select_count_for(path)
    count = 0
    ActiveRecord::Base.connection.clear_query_cache
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA"
      count += 1 if payload[:sql].lstrip.match?(/\ASELECT\b/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { get path }
    count
  end
end
