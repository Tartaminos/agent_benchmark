require "test_helper"

class Api::SellerOrdersTest < ActionDispatch::IntegrationTest
  setup do
    @customer = Customer.create!(
      customer_id: "seller_orders_customer_0000001",
      customer_unique_id: "seller_orders_unique_00000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @seller = Seller.create!(
      seller_id: "seller_primary_0000000000000001",
      zip_code_prefix: "20001",
      city: "rio de janeiro",
      state: "RJ"
    )
    @other_seller = Seller.create!(
      seller_id: "seller_other_00000000000000001",
      zip_code_prefix: "30110",
      city: "belo horizonte",
      state: "MG"
    )
    @product_one = Product.create!(
      product_id: "product_primary_000000000000001",
      category_name: "moveis_decoracao"
    )
    @product_two = Product.create!(
      product_id: "product_primary_000000000000002",
      category_name: nil
    )
    @other_product = Product.create!(
      product_id: "product_other_0000000000000001",
      category_name: "telefonia"
    )

    @aggregate_order = create_order(
      "order_primary_00000000000000001",
      purchase_at: Time.utc(2024, 1, 1, 12, 0, 0, 123_000)
    )
    add_item(@aggregate_order, @seller, @product_one, 1, price: "10.10", freight: "0.90")
    add_item(@aggregate_order, @seller, @product_one, 2, price: "2.20", freight: "0.30")
    add_item(@aggregate_order, @seller, @product_two, 3, price: "0.01", freight: "0.02")
    add_item(@aggregate_order, @other_seller, @other_product, 4, price: "100.00", freight: "20.00")

    tied_at = Time.utc(2024, 1, 2, 12)
    @tie_a = create_order("order_tie_a_00000000000000000001", purchase_at: tied_at)
    @tie_b = create_order("order_tie_b_00000000000000000001", purchase_at: tied_at)
    add_item(@tie_a, @seller, @product_one, 1, price: "1.00", freight: "0.00")
    add_item(@tie_b, @seller, @product_two, 1, price: "2.00", freight: "0.00")
  end

  test "returns distinct seller-scoped orders, aggregates, products, and public identifiers" do
    get "/api/sellers/#{@seller.seller_id}/orders"

    assert_response :ok
    assert_equal "application/json", response.media_type

    body = response.parsed_body
    assert_equal @seller.seller_id, body.fetch("seller_id")
    assert_equal 1, body.fetch("page")
    assert_equal 20, body.fetch("per_page")
    assert_equal 3, body.fetch("total_orders")
    assert_equal 3, body.fetch("orders").size

    order = body.fetch("orders").find { |entry| entry.fetch("order_id") == @aggregate_order.order_id }
    assert_equal(
      {
        "order_id" => @aggregate_order.order_id,
        "status" => "delivered",
        "purchase_at" => "2024-01-01T12:00:00.123Z",
        "item_count" => 3,
        "items_value" => "12.31",
        "freight_value" => "1.22",
        "total_value" => "13.53",
        "products" => [
          {
            "product_id" => @product_one.product_id,
            "category_name" => "moveis_decoracao"
          },
          {
            "product_id" => @product_two.product_id,
            "category_name" => nil
          }
        ]
      },
      order
    )
    refute_includes nested_keys(body), "id"
  end

  test "uses deterministic ordering and explicit pagination" do
    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: "2", per_page: "1" }

    assert_response :ok
    body = response.parsed_body
    assert_equal 2, body.fetch("page")
    assert_equal 1, body.fetch("per_page")
    assert_equal 3, body.fetch("total_orders")
    assert_equal [@tie_b.order_id], body.fetch("orders").pluck("order_id")

    get "/api/sellers/#{@seller.seller_id}/orders", params: { page: "1", per_page: "100" }
    assert_response :ok
    assert_equal [@tie_a.order_id, @tie_b.order_id, @aggregate_order.order_id],
      response.parsed_body.fetch("orders").pluck("order_id")
  end

  test "returns an empty page beyond the available orders, including a huge valid page" do
    ["99", "999999999999999999999999999999999999999999"].each do |page|
      get "/api/sellers/#{@seller.seller_id}/orders", params: { page: page, per_page: "2" }

      assert_response :ok
      assert_equal 3, response.parsed_body.fetch("total_orders")
      assert_empty response.parsed_body.fetch("orders")
    end
  end

  test "rejects invalid scalar pagination before attempting seller lookup" do
    invalid_queries = [
      "page=0", "page=-1", "page=abc", "page=1.0", "page=+1", "page=%201",
      "per_page=0", "per_page=-10", "per_page=101", "per_page=abc", "per_page=1.0"
    ]

    invalid_queries.each do |query|
      get "/api/sellers/unknown_seller/orders?#{query}"

      assert_response :unprocessable_content, "expected 422 for #{query}"
      assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
    end
  end

  test "rejects non-scalar pagination parameters" do
    ["page[]=1", "page[value]=1", "per_page[]=20", "per_page[value]=20"].each do |query|
      get "/api/sellers/#{@seller.seller_id}/orders?#{query}"

      assert_response :unprocessable_content, "expected 422 for #{query}"
      assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
    end
  end

  test "returns not found for an unknown external seller id and does not accept an internal id" do
    ["unknown_seller", @seller.id.to_s].each do |seller_id|
      get "/api/sellers/#{seller_id}/orders"

      assert_response :not_found
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
    end
  end

  test "keeps SELECT count bounded as the page size grows" do
    47.times do |index|
      order = create_order(
        format("order_perf_%021d", index),
        purchase_at: Time.utc(2023, 12, 31) - index.seconds
      )
      add_item(order, @seller, @product_one, 1, price: "1.00", freight: "0.10")
    end

    small_page_count = select_count do
      get "/api/sellers/#{@seller.seller_id}/orders", params: { page: "1", per_page: "5" }
      assert_response :ok
      assert_equal 5, response.parsed_body.fetch("orders").size
    end
    large_page_count = select_count do
      get "/api/sellers/#{@seller.seller_id}/orders", params: { page: "1", per_page: "50" }
      assert_response :ok
      assert_equal 50, response.parsed_body.fetch("orders").size
    end

    assert_operator (small_page_count - large_page_count).abs, :<=, 1,
      "expected effectively constant SELECT count, got #{small_page_count} and #{large_page_count}"
    assert_operator [small_page_count, large_page_count].max, :<=, 5,
      "expected a bounded query plan, got #{small_page_count} and #{large_page_count} SELECTs"
  end

  private

  def create_order(order_id, purchase_at:)
    Order.create!(
      order_id: order_id,
      customer: @customer,
      status: "delivered",
      purchase_at: purchase_at,
      estimated_delivery_at: purchase_at + 7.days
    )
  end

  def add_item(order, seller, product, item_number, price:, freight:)
    order.order_items.create!(
      order_item_id: item_number,
      product: product,
      seller: seller,
      shipping_limit_at: order.purchase_at + 1.day,
      price: BigDecimal(price),
      freight_value: BigDecimal(freight)
    )
  end

  def select_count
    count = 0
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload.fetch(:sql)
      count += 1 if sql.match?(/\ASELECT\b/i) && payload[:name] != "SCHEMA" && !payload[:cached]
    end

    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    end
    count
  end

  def nested_keys(value)
    case value
    when Hash
      value.keys + value.values.flat_map { |nested| nested_keys(nested) }
    when Array
      value.flat_map { |nested| nested_keys(nested) }
    else
      []
    end
  end
end
