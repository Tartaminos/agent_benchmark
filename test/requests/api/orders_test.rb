require "test_helper"

class Api::OrdersTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    primary_customer = Customer.create!(
      customer_id: "customer_external_primary",
      customer_unique_id: "customer_unique_primary",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    no_reviews_customer = Customer.create!(
      customer_id: "customer_external_no_reviews",
      customer_unique_id: "customer_unique_no_reviews",
      zip_code_prefix: "20001",
      city: "rio de janeiro",
      state: "RJ"
    )
    @primary_order = Order.create!(
      order_id: "external_order_primary",
      customer: primary_customer,
      status: "delivered",
      purchase_at: Time.utc(2017, 10, 2, 10, 56, 33),
      approved_at: Time.utc(2017, 10, 2, 11, 7, 15),
      delivered_carrier_at: Time.utc(2017, 10, 4, 19, 55),
      delivered_customer_at: Time.utc(2017, 10, 10, 21, 25, 13),
      estimated_delivery_at: Time.utc(2017, 10, 18)
    )
    @no_reviews_order = Order.create!(
      order_id: "external_order_no_reviews",
      customer: no_reviews_customer,
      status: "processing",
      purchase_at: Time.utc(2018, 1, 2, 3, 4, 5),
      approved_at: nil,
      delivered_carrier_at: nil,
      delivered_customer_at: nil,
      estimated_delivery_at: Time.utc(2018, 1, 20)
    )

    first_product = Product.create!(product_id: "product_external_first")
    second_product = Product.create!(product_id: "product_external_second")
    zero_value_product = Product.create!(product_id: "product_external_zero")
    first_seller = Seller.create!(
      seller_id: "seller_external_first", zip_code_prefix: "01001",
      city: "sao paulo", state: "SP"
    )
    second_seller = Seller.create!(
      seller_id: "seller_external_second", zip_code_prefix: "30100",
      city: "belo horizonte", state: "MG"
    )

    # Insert collections in reverse business order so the request must apply ordering.
    OrderItem.create!(
      order: @primary_order, product: second_product, seller: second_seller,
      order_item_id: 2, shipping_limit_at: Time.utc(2017, 10, 6),
      price: "10.10", freight_value: "0.05"
    )
    OrderItem.create!(
      order: @primary_order, product: first_product, seller: first_seller,
      order_item_id: 1, shipping_limit_at: Time.utc(2017, 10, 5),
      price: "2.00", freight_value: "3.40"
    )
    OrderItem.create!(
      order: @no_reviews_order, product: zero_value_product, seller: first_seller,
      order_item_id: 1, shipping_limit_at: Time.utc(2018, 1, 5),
      price: "0.00", freight_value: "0.00"
    )
    OrderPayment.create!(
      order: @primary_order, payment_sequential: 2, payment_type: "voucher",
      payment_installments: 1, payment_value: "5.55"
    )
    OrderPayment.create!(
      order: @primary_order, payment_sequential: 1, payment_type: "credit_card",
      payment_installments: 2, payment_value: "10.00"
    )
    OrderPayment.create!(
      order: @no_reviews_order, payment_sequential: 1, payment_type: "voucher",
      payment_installments: 1, payment_value: "0.00"
    )
    OrderReview.create!(
      order: @primary_order, review_id: "review_external_with_comments", score: 5,
      comment_title: "excelente", comment_message: "chegou cedo",
      creation_at: Time.utc(2017, 10, 11), answer_at: Time.utc(2017, 10, 12, 3, 43, 48)
    )
    OrderReview.create!(
      order: @primary_order, review_id: "review_external_without_comment", score: 3,
      comment_title: nil, comment_message: nil,
      creation_at: Time.utc(2017, 10, 13, 4, 5, 6), answer_at: Time.utc(2017, 10, 14, 7, 8, 9)
    )
  end

  test "show returns the exact public contract with ordered collections and totals" do
    sql_counter = ActiveRecord::Assertions::QueryAssertions::SQLCounter.new
    ActiveRecord::Base.lease_connection.materialize_transactions
    ActiveSupport::Notifications.subscribed(sql_counter, "sql.active_record") do
      get "/api/orders/#{@primary_order.order_id}"
    end

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_operator sql_counter.log.size, :<=, 7,
                    "expected a bounded eager-loaded query graph, got: #{sql_counter.log.join("\n\n")}"
    assert sql_counter.log.all? { |sql| sql.match?(/\ASELECT\b/i) },
           "expected a read-only endpoint, got: #{sql_counter.log.join("\n\n")}"

    body = response.parsed_body
    assert_equal %w[
      order_id status purchase_at approved_at delivered_carrier_at
      delivered_customer_at estimated_delivery_at customer items payments
      reviews totals
    ].sort, body.keys.sort
    assert_equal(
      {
        "order_id" => "external_order_primary",
        "status" => "delivered",
        "purchase_at" => "2017-10-02T10:56:33.000Z",
        "approved_at" => "2017-10-02T11:07:15.000Z",
        "delivered_carrier_at" => "2017-10-04T19:55:00.000Z",
        "delivered_customer_at" => "2017-10-10T21:25:13.000Z",
        "estimated_delivery_at" => "2017-10-18T00:00:00.000Z"
      },
      body.slice(
        "order_id", "status", "purchase_at", "approved_at",
        "delivered_carrier_at", "delivered_customer_at", "estimated_delivery_at"
      )
    )
    assert_equal(
      {
        "customer_id" => "customer_external_primary",
        "customer_unique_id" => "customer_unique_primary",
        "city" => "sao paulo",
        "state" => "SP"
      },
      body.fetch("customer")
    )
    assert_equal(
      [
        {
          "order_item_id" => 1,
          "product_id" => "product_external_first",
          "seller_id" => "seller_external_first",
          "price" => "2.00",
          "freight_value" => "3.40"
        },
        {
          "order_item_id" => 2,
          "product_id" => "product_external_second",
          "seller_id" => "seller_external_second",
          "price" => "10.10",
          "freight_value" => "0.05"
        }
      ],
      body.fetch("items")
    )
    assert_equal(
      [
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
          "payment_value" => "5.55"
        }
      ],
      body.fetch("payments")
    )
    assert_equal(
      {
        "items" => "12.10",
        "freight" => "3.45",
        "order" => "15.55",
        "paid" => "15.55"
      },
      body.fetch("totals")
    )

    reviews_by_id = body.fetch("reviews").index_by { |review| review.fetch("review_id") }
    assert_equal %w[review_external_with_comments review_external_without_comment].sort,
                 reviews_by_id.keys.sort
    assert_equal(
      {
        "review_id" => "review_external_with_comments",
        "score" => 5,
        "comment_title" => "excelente",
        "comment_message" => "chegou cedo",
        "creation_at" => "2017-10-11T00:00:00.000Z",
        "answer_at" => "2017-10-12T03:43:48.000Z"
      },
      reviews_by_id.fetch("review_external_with_comments")
    )
    assert_equal(
      {
        "review_id" => "review_external_without_comment",
        "score" => 3,
        "comment_title" => nil,
        "comment_message" => nil,
        "creation_at" => "2017-10-13T04:05:06.000Z",
        "answer_at" => "2017-10-14T07:08:09.000Z"
      },
      reviews_by_id.fetch("review_external_without_comment")
    )
  end

  test "show represents absent reviews nullable order timestamps and zero money exactly" do
    get "/api/orders/#{@no_reviews_order.order_id}"

    assert_response :success
    body = response.parsed_body
    assert_equal [], body.fetch("reviews")
    assert_nil body.fetch("approved_at")
    assert_nil body.fetch("delivered_carrier_at")
    assert_nil body.fetch("delivered_customer_at")
    assert_equal "0.00", body.dig("items", 0, "price")
    assert_equal "0.00", body.dig("items", 0, "freight_value")
    assert_equal "0.00", body.dig("payments", 0, "payment_value")
    assert_equal(
      { "items" => "0.00", "freight" => "0.00", "order" => "0.00", "paid" => "0.00" },
      body.fetch("totals")
    )
  end

  test "show returns the exact not found response for an unknown external order id" do
    get "/api/orders/does-not-exist"

    assert_response :not_found
    assert_equal "application/json", response.media_type
    assert_equal({ "error" => "order_not_found" }, response.parsed_body)
  end
end
