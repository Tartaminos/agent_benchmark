require "test_helper"

class Api::OrdersTest < ActionDispatch::IntegrationTest
  setup do
    customer = Customer.create!(
      customer_id: "test_customer_external_00000001",
      customer_unique_id: "test_customer_unique_000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )

    @order = Order.create!(
      order_id: "test_order_external_00000000001",
      customer: customer,
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

  private

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
