require "test_helper"

class Api::OrdersTest < ActionDispatch::IntegrationTest
  setup do
    @customer = Customer.create!(
      customer_id: "test_customer_external_00000001",
      customer_unique_id: "test_customer_unique_000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )

    @order = Order.create!(
      order_id: "test_order_external_00000000001",
      customer: @customer,
      status: "delivered",
      purchase_at: Time.utc(2017, 10, 2, 10, 56, 33, 123_000),
      approved_at: nil,
      delivered_carrier_at: Time.utc(2017, 10, 4, 19, 55, 0),
      delivered_customer_at: nil,
      estimated_delivery_at: Time.utc(2017, 10, 18)
    )

    product_one = Product.create!(product_id: "test_product_external_000000001")
    product_two = Product.create!(product_id: "test_product_external_000000002")
    seller_one = Seller.create!(
      seller_id: "test_seller_external_0000000001",
      zip_code_prefix: "20001",
      city: "rio de janeiro",
      state: "RJ"
    )
    seller_two = Seller.create!(
      seller_id: "test_seller_external_0000000002",
      zip_code_prefix: "30110",
      city: "belo horizonte",
      state: "MG"
    )

    @order.order_items.create!(
      order_item_id: 2,
      product: product_two,
      seller: seller_two,
      shipping_limit_at: Time.utc(2017, 10, 6),
      price: BigDecimal("2.30"),
      freight_value: BigDecimal("0.70")
    )
    @order.order_items.create!(
      order_item_id: 1,
      product: product_one,
      seller: seller_one,
      shipping_limit_at: Time.utc(2017, 10, 5),
      price: BigDecimal("10.00"),
      freight_value: BigDecimal("0.00")
    )

    @order.order_payments.create!(
      payment_sequential: 2,
      payment_type: "voucher",
      payment_installments: 1,
      payment_value: BigDecimal("3.00")
    )
    @order.order_payments.create!(
      payment_sequential: 1,
      payment_type: "credit_card",
      payment_installments: 2,
      payment_value: BigDecimal("10.00")
    )

    @order.order_reviews.create!(
      review_id: "test_review_external_0000000002",
      score: 3,
      comment_title: "Entrega",
      comment_message: "Chegou com atraso",
      creation_at: Time.utc(2017, 10, 12, 1, 2, 3, 456_000),
      answer_at: Time.utc(2017, 10, 13, 4, 5, 6, 789_000)
    )
    @order.order_reviews.create!(
      review_id: "test_review_external_0000000001",
      score: 5,
      comment_title: nil,
      comment_message: nil,
      creation_at: Time.utc(2017, 10, 11),
      answer_at: Time.utc(2017, 10, 12, 3, 43, 48)
    )
  end

  test "returns the complete public order contract for an external order id" do
    get "/api/orders/#{@order.order_id}"

    assert_response :ok
    assert_equal "application/json", response.media_type

    actual = response.parsed_body
    expected = {
      "order_id" => "test_order_external_00000000001",
      "status" => "delivered",
      "purchase_at" => "2017-10-02T10:56:33.123Z",
      "approved_at" => nil,
      "delivered_carrier_at" => "2017-10-04T19:55:00.000Z",
      "delivered_customer_at" => nil,
      "estimated_delivery_at" => "2017-10-18T00:00:00.000Z",
      "customer" => {
        "customer_id" => "test_customer_external_00000001",
        "customer_unique_id" => "test_customer_unique_000000001",
        "city" => "sao paulo",
        "state" => "SP"
      },
      "items" => [
        {
          "order_item_id" => 1,
          "product_id" => "test_product_external_000000001",
          "seller_id" => "test_seller_external_0000000001",
          "price" => "10.00",
          "freight_value" => "0.00"
        },
        {
          "order_item_id" => 2,
          "product_id" => "test_product_external_000000002",
          "seller_id" => "test_seller_external_0000000002",
          "price" => "2.30",
          "freight_value" => "0.70"
        }
      ],
      "payments" => [
        {
          "payment_sequential" => 1,
          "payment_type" => "credit_card",
          "payment_installments" => 2,
          "payment_value" => "10.00"
        },
        {
          "payment_sequential" => 2,
          "payment_type" => "voucher",
          "payment_installments" => 1,
          "payment_value" => "3.00"
        }
      ],
      "reviews" => [
        {
          "review_id" => "test_review_external_0000000001",
          "score" => 5,
          "comment_title" => nil,
          "comment_message" => nil,
          "creation_at" => "2017-10-11T00:00:00.000Z",
          "answer_at" => "2017-10-12T03:43:48.000Z"
        },
        {
          "review_id" => "test_review_external_0000000002",
          "score" => 3,
          "comment_title" => "Entrega",
          "comment_message" => "Chegou com atraso",
          "creation_at" => "2017-10-12T01:02:03.456Z",
          "answer_at" => "2017-10-13T04:05:06.789Z"
        }
      ],
      "totals" => {
        "items" => "12.30",
        "freight" => "0.70",
        "order" => "13.00",
        "paid" => "13.00"
      }
    }

    actual["reviews"].sort_by! { |review| review.fetch("review_id") }
    expected["reviews"].sort_by! { |review| review.fetch("review_id") }

    assert_equal expected, actual
    refute_includes nested_keys(actual), "id"
  end

  test "returns an empty reviews array when the order has no reviews" do
    OrderReview.where(order: @order).delete_all

    get "/api/orders/#{@order.order_id}"

    assert_response :ok
    assert_equal [], response.parsed_body.fetch("reviews")
  end

  test "returns the exact not found response for an unknown external order id" do
    get "/api/orders/unknown_order_external_id"

    assert_response :not_found
    assert_equal({ "error" => "order_not_found" }, response.parsed_body)
  end

  test "does not accept the internal database id as the public identifier" do
    get "/api/orders/#{@order.id}"

    assert_response :not_found
    assert_equal({ "error" => "order_not_found" }, response.parsed_body)
  end

  test "lists the exact public contract with defaults and every delivery classification" do
    estimated_at = Time.utc(2024, 1, 10, 12)
    on_time = create_list_order(
      "list_on_time_0000000000000001",
      purchase_at: Time.utc(2024, 1, 2, 3, 4, 5, 678_000),
      estimated_at: estimated_at,
      delivered_at: estimated_at
    )
    late = create_list_order(
      "list_late_000000000000000001",
      purchase_at: Time.utc(2024, 1, 3),
      estimated_at: estimated_at,
      delivered_at: estimated_at + 1.second
    )

    get "/api/orders"

    assert_response :ok
    assert_equal "application/json", response.media_type
    body = response.parsed_body
    assert_equal(
      {
        "page" => 1,
        "per_page" => 25,
        "total_count" => 3,
        "total_pages" => 1
      },
      body.except("orders")
    )
    assert_equal [ late.order_id, on_time.order_id, @order.order_id ], body.fetch("orders").pluck("order_id")
    assert_equal(
      {
        "order_id" => on_time.order_id,
        "status" => "delivered",
        "purchase_at" => "2024-01-02T03:04:05.678Z",
        "estimated_delivery_at" => "2024-01-10T12:00:00.000Z",
        "delivered_customer_at" => "2024-01-10T12:00:00.000Z",
        "delivery_status" => "on_time"
      },
      body.fetch("orders").find { |order| order.fetch("order_id") == on_time.order_id }
    )
    assert_equal "late", body.fetch("orders").first.fetch("delivery_status")
    assert_equal "pending", body.fetch("orders").last.fetch("delivery_status")
    assert_nil body.fetch("orders").last.fetch("delivered_customer_at")
    assert_equal %w[delivered_customer_at delivery_status estimated_delivery_at order_id purchase_at status],
      body.fetch("orders").first.keys.sort
    refute_includes nested_keys(body), "id"
  end

  test "filters all classifications and computes metadata from matching orders" do
    estimated_at = Time.utc(2024, 1, 10)
    second_pending = create_list_order(
      "filter_pending_000000000000001",
      purchase_at: Time.utc(2024, 1, 4),
      estimated_at: estimated_at,
      delivered_at: nil
    )
    early = create_list_order(
      "filter_early_0000000000000001",
      purchase_at: Time.utc(2024, 1, 3),
      estimated_at: estimated_at,
      delivered_at: estimated_at - 1.second
    )
    boundary = create_list_order(
      "filter_boundary_0000000000001",
      purchase_at: Time.utc(2024, 1, 2),
      estimated_at: estimated_at,
      delivered_at: estimated_at
    )
    late = create_list_order(
      "filter_late_00000000000000001",
      purchase_at: Time.utc(2024, 1, 1),
      estimated_at: estimated_at,
      delivered_at: estimated_at + 1.second
    )

    {
      "pending" => [ second_pending.order_id, @order.order_id ],
      "on_time" => [ early.order_id, boundary.order_id ],
      "late" => [ late.order_id ]
    }.each do |status, expected_ids|
      get "/api/orders", params: { delivery_status: status, page: "1", per_page: "1" }

      assert_response :ok
      body = response.parsed_body
      assert_equal expected_ids.length, body.fetch("total_count")
      assert_equal expected_ids.length, body.fetch("total_pages")
      assert_equal [ expected_ids.first ], body.fetch("orders").pluck("order_id")
      assert_equal [ status ], body.fetch("orders").pluck("delivery_status").uniq
    end
  end

  test "paginates with deterministic tie ordering and accepts the maximum page size" do
    tied_at = Time.utc(2024, 1, 5)
    tie_b = create_list_order(
      "pagination_tie_b_0000000000001",
      purchase_at: tied_at,
      estimated_at: tied_at + 1.day,
      delivered_at: nil
    )
    tie_a = create_list_order(
      "pagination_tie_a_0000000000001",
      purchase_at: tied_at,
      estimated_at: tied_at + 1.day,
      delivered_at: nil
    )

    get "/api/orders", params: { page: "2", per_page: "1" }

    assert_response :ok
    body = response.parsed_body
    assert_equal 2, body.fetch("page")
    assert_equal 1, body.fetch("per_page")
    assert_equal 3, body.fetch("total_count")
    assert_equal 3, body.fetch("total_pages")
    assert_equal [ tie_b.order_id ], body.fetch("orders").pluck("order_id")

    get "/api/orders", params: { page: "1", per_page: "100" }

    assert_response :ok
    assert_equal 100, response.parsed_body.fetch("per_page")
    assert_equal [ tie_a.order_id, tie_b.order_id, @order.order_id ],
      response.parsed_body.fetch("orders").pluck("order_id")
  end

  test "returns stable metadata for an empty filter and huge out-of-range pages" do
    get "/api/orders", params: { delivery_status: "late" }

    assert_response :ok
    assert_equal 0, response.parsed_body.fetch("total_count")
    assert_equal 0, response.parsed_body.fetch("total_pages")
    assert_empty response.parsed_body.fetch("orders")

    [ "99", "999999999999999999999999999999999999999999" ].each do |page|
      get "/api/orders", params: { page: page, per_page: "25" }

      assert_response :ok
      body = response.parsed_body
      assert_equal page.to_i, body.fetch("page")
      assert_equal 1, body.fetch("total_count")
      assert_equal 1, body.fetch("total_pages")
      assert_empty body.fetch("orders")
    end
  end

  test "rejects invalid scalar and structured pagination before delivery status validation" do
    invalid_queries = [
      "page=", "page=0", "page=-1", "page=abc", "page=1.0", "page=+1", "page=%201", "page=%D9%A1",
      "per_page=", "per_page=0", "per_page=-1", "per_page=101", "per_page=abc", "per_page=1.0",
      "page[]=1", "page[value]=1", "per_page[]=25", "per_page[value]=25"
    ]

    invalid_queries.each do |query|
      get "/api/orders?delivery_status=unsupported&#{query}"

      assert_response :unprocessable_content, "expected 422 for #{query}"
      assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
    end
  end

  test "rejects blank, unsupported, and structured delivery filters with the exact error" do
    invalid_queries = [
      "delivery_status=", "delivery_status=Pending", "delivery_status=unsupported",
      "delivery_status[]=pending", "delivery_status[value]=pending"
    ]

    invalid_queries.each do |query|
      get "/api/orders?#{query}"

      assert_response :unprocessable_content, "expected 422 for #{query}"
      assert_equal({ "error" => "invalid_delivery_status" }, response.parsed_body)
    end
  end

  private

  def create_list_order(order_id, purchase_at:, estimated_at:, delivered_at:)
    Order.create!(
      order_id: order_id,
      customer: @customer,
      status: "delivered",
      purchase_at: purchase_at,
      estimated_delivery_at: estimated_at,
      delivered_customer_at: delivered_at
    )
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
