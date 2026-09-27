require "test_helper"

class Api::OrderDeliveryStatusesControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @customer = Customer.create!(
      customer_id: "deliverycustomer0000000000000001",
      customer_unique_id: "deliveryunique00000000000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )

    create_order(1, purchase_at: "2024-01-05 12:00:00 UTC", delivered_at: nil, estimated_at: "2024-01-10 12:00:00 UTC", status: "processing")
    create_order(2, purchase_at: "2024-01-04 12:00:00 UTC", delivered_at: "2024-01-10 12:00:00 UTC", estimated_at: "2024-01-10 12:00:00 UTC")
    create_order(3, purchase_at: "2024-01-03 12:00:00 UTC", delivered_at: "2024-01-09 12:00:00 UTC", estimated_at: "2024-01-10 12:00:00 UTC")
    create_order(4, purchase_at: "2024-01-02 12:00:00 UTC", delivered_at: "2024-01-11 12:00:00 UTC", estimated_at: "2024-01-10 12:00:00 UTC")
    create_order(5, purchase_at: "2024-01-02 12:00:00 UTC", delivered_at: nil, estimated_at: "2024-01-10 12:00:00 UTC")
  end

  test "classifies pending, equality and early delivery, and late delivery with the public representation" do
    get "/api/orders", params: { per_page: 10 }

    assert_response :success
    body = response.parsed_body
    assert_equal({
      "page" => 1,
      "per_page" => 10,
      "total_orders" => 5,
      "total_pages" => 1
    }, body.except("orders"))
    assert_equal [order_id(1), order_id(2), order_id(3), order_id(4), order_id(5)], body["orders"].map { |order| order["order_id"] }
    assert_equal %w[pending on_time on_time late pending], body["orders"].map { |order| order["delivery_status"] }

    pending = body["orders"].first
    assert_equal %w[delivered_customer_at delivery_status estimated_delivery_at order_id purchase_at status], pending.keys.sort
    assert_equal "processing", pending["status"]
    assert_equal "2024-01-05T12:00:00.000Z", pending["purchase_at"]
    assert_equal "2024-01-10T12:00:00.000Z", pending["estimated_delivery_at"]
    assert_nil pending["delivered_customer_at"]
    assert_equal "2024-01-10T12:00:00.000Z", body["orders"][1]["delivered_customer_at"]
    refute_includes pending.keys, "id"
    refute_includes pending.keys, "customer_id"
  end

  test "filters each classification and calculates metadata from the filtered relation" do
    {
      "pending" => [order_id(1), order_id(5)],
      "on_time" => [order_id(2), order_id(3)],
      "late" => [order_id(4)]
    }.each do |status, expected_ids|
      get "/api/orders", params: { delivery_status: status, per_page: 1 }

      assert_response :success
      body = response.parsed_body
      assert_equal status, body.fetch("orders").first.fetch("delivery_status")
      assert_equal expected_ids.first, body.fetch("orders").first.fetch("order_id")
      assert_equal expected_ids.length, body.fetch("total_orders")
      assert_equal expected_ids.length, body.fetch("total_pages")
    end
  end

  test "applies the delivery filter in SQL for both count and page retrieval" do
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] if payload[:sql]&.match?(/\bFROM\s+"?orders"?\b/i)
    end

    get "/api/orders", params: { delivery_status: "late" }
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_response :success
    filtered_statements = statements.grep(/delivered_customer_at\s*>\s*estimated_delivery_at/i)
    assert_operator filtered_statements.length, :>=, 2, "expected SQL-filtered count and page queries, got: #{statements.inspect}"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test "returns an empty filtered page with zero totals" do
    Order.update_all(delivered_customer_at: nil)

    get "/api/orders", params: { delivery_status: "late" }

    assert_response :success
    assert_equal [], response.parsed_body["orders"]
    assert_equal 0, response.parsed_body["total_orders"]
    assert_equal 0, response.parsed_body["total_pages"]
  end

  test "uses deterministic offsets for page and per_page" do
    get "/api/orders", params: { page: 2, per_page: 2 }

    assert_response :success
    assert_equal 2, response.parsed_body["page"]
    assert_equal 2, response.parsed_body["per_page"]
    assert_equal 5, response.parsed_body["total_orders"]
    assert_equal 3, response.parsed_body["total_pages"]
    assert_equal [order_id(3), order_id(4)], response.parsed_body["orders"].map { |order| order["order_id"] }
  end

  test "defaults to 25 rows and caps a positive per_page at 100" do
    101.times do |index|
      create_order(100 + index, purchase_at: "2023-01-01 00:00:00 UTC", delivered_at: nil, estimated_at: "2023-01-10 00:00:00 UTC")
    end

    get "/api/orders"
    assert_response :success
    assert_equal 1, response.parsed_body["page"]
    assert_equal 25, response.parsed_body["per_page"]
    assert_equal 25, response.parsed_body["orders"].length
    assert_equal 106, response.parsed_body["total_orders"]
    assert_equal 5, response.parsed_body["total_pages"]

    get "/api/orders", params: { per_page: 101 }
    assert_response :success
    assert_equal 100, response.parsed_body["per_page"]
    assert_equal 100, response.parsed_body["orders"].length
    assert_equal 2, response.parsed_body["total_pages"]
  end

  test "rejects invalid scalar, empty, and structured delivery filters exactly" do
    [
      { delivery_status: "lost" },
      { delivery_status: "" },
      { delivery_status: ["late"] },
      { delivery_status: { value: "late" } }
    ].each do |params|
      get "/api/orders", params: params

      assert_response :unprocessable_content, "wrong status for #{params.inspect}"
      assert_equal({ "error" => "invalid_delivery_status" }, response.parsed_body, "wrong body for #{params.inspect}")
    end
  end

  test "rejects malformed, nonpositive, and structured pagination exactly" do
    [
      { page: "0" },
      { page: "-1" },
      { page: "abc" },
      { page: "1.5" },
      { page: ["1"] },
      { per_page: "0" },
      { per_page: "-1" },
      { per_page: "abc" },
      { per_page: { value: "25" } }
    ].each do |params|
      get "/api/orders", params: params

      assert_response :unprocessable_content, "wrong status for #{params.inspect}"
      assert_equal({ "error" => "invalid_pagination" }, response.parsed_body, "wrong body for #{params.inspect}")
    end
  end

  private

  def create_order(number, purchase_at:, delivered_at:, estimated_at:, status: "delivered")
    Order.create!(
      order_id: order_id(number),
      customer: @customer,
      status: status,
      purchase_at: purchase_at,
      delivered_customer_at: delivered_at,
      estimated_delivery_at: estimated_at
    )
  end

  def order_id(number)
    format("delivery%024d", number)
  end
end
