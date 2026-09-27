require "test_helper"

class Api::OrdersControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    customer_one = Customer.create!(customer_id: "customer000000000000000000000001", customer_unique_id: "unique00000000000000000000000001", zip_code_prefix: "01001", city: "sao paulo", state: "SP")
    customer_two = Customer.create!(customer_id: "customer000000000000000000000002", customer_unique_id: "unique00000000000000000000000002", zip_code_prefix: "20001", city: "rio de janeiro", state: "RJ")
    product_one = Product.create!(product_id: "product0000000000000000000000001", category_name: "category_one")
    product_two = Product.create!(product_id: "product0000000000000000000000002", category_name: "category_two")
    seller_one = Seller.create!(seller_id: "seller00000000000000000000000001", zip_code_prefix: "01001", city: "sao paulo", state: "SP")
    seller_two = Seller.create!(seller_id: "seller00000000000000000000000002", zip_code_prefix: "20001", city: "rio de janeiro", state: "RJ")
    @order_one = Order.create!(order_id: "order000000000000000000000000001", customer: customer_one, status: "delivered", purchase_at: "2017-10-02 10:56:33 UTC", approved_at: "2017-10-02 11:07:15 UTC", delivered_carrier_at: "2017-10-04 19:55:00 UTC", delivered_customer_at: "2017-10-10 21:25:13 UTC", estimated_delivery_at: "2017-10-18 00:00:00 UTC")
    @order_two = Order.create!(order_id: "order000000000000000000000000002", customer: customer_two, status: "processing", purchase_at: "2018-01-02 03:04:05 UTC", approved_at: nil, delivered_carrier_at: nil, delivered_customer_at: nil, estimated_delivery_at: "2018-01-20 00:00:00 UTC")
    OrderItem.create!(order: @order_one, product: product_one, seller: seller_one, order_item_id: 2, shipping_limit_at: "2017-10-10 UTC", price: 10, freight_value: 0.8)
    OrderItem.create!(order: @order_one, product: product_two, seller: seller_two, order_item_id: 1, shipping_limit_at: "2017-10-10 UTC", price: 29.99, freight_value: 8.72)
    OrderPayment.create!(order: @order_one, payment_sequential: 2, payment_type: "voucher", payment_installments: 1, payment_value: 10)
    OrderPayment.create!(order: @order_one, payment_sequential: 1, payment_type: "credit_card", payment_installments: 2, payment_value: 39.51)
    OrderReview.create!(id: 102, order: @order_one, review_id: "review00000000000000000000000002", score: 5, comment_title: nil, comment_message: nil, creation_at: "2017-10-13 00:00:00 UTC", answer_at: "2017-10-14 03:43:48 UTC")
    OrderReview.create!(id: 101, order: @order_one, review_id: "review00000000000000000000000001", score: 4, comment_title: "Good", comment_message: "Arrived safely", creation_at: "2017-10-11 00:00:00 UTC", answer_at: "2017-10-12 03:43:48 UTC")
  end

  test "returns complete order details by external order id" do
    get "/api/orders/#{@order_one.order_id}"

    assert_response :success
    assert_equal(
      {
        "order_id" => "order000000000000000000000000001",
        "status" => "delivered",
        "purchase_at" => "2017-10-02T10:56:33.000Z",
        "approved_at" => "2017-10-02T11:07:15.000Z",
        "delivered_carrier_at" => "2017-10-04T19:55:00.000Z",
        "delivered_customer_at" => "2017-10-10T21:25:13.000Z",
        "estimated_delivery_at" => "2017-10-18T00:00:00.000Z",
        "customer" => {
          "customer_id" => "customer000000000000000000000001",
          "customer_unique_id" => "unique00000000000000000000000001",
          "city" => "sao paulo",
          "state" => "SP"
        },
        "items" => [
          {
            "order_item_id" => 1,
            "product_id" => "product0000000000000000000000002",
            "seller_id" => "seller00000000000000000000000002",
            "price" => "29.99",
            "freight_value" => "8.72"
          },
          {
            "order_item_id" => 2,
            "product_id" => "product0000000000000000000000001",
            "seller_id" => "seller00000000000000000000000001",
            "price" => "10.00",
            "freight_value" => "0.80"
          }
        ],
        "payments" => [
          {
            "payment_sequential" => 1,
            "payment_type" => "credit_card",
            "payment_installments" => 2,
            "payment_value" => "39.51"
          },
          {
            "payment_sequential" => 2,
            "payment_type" => "voucher",
            "payment_installments" => 1,
            "payment_value" => "10.00"
          }
        ],
        "reviews" => [
          {
            "review_id" => "review00000000000000000000000001",
            "score" => 4,
            "comment_title" => "Good",
            "comment_message" => "Arrived safely",
            "creation_at" => "2017-10-11T00:00:00.000Z",
            "answer_at" => "2017-10-12T03:43:48.000Z"
          },
          {
            "review_id" => "review00000000000000000000000002",
            "score" => 5,
            "comment_title" => nil,
            "comment_message" => nil,
            "creation_at" => "2017-10-13T00:00:00.000Z",
            "answer_at" => "2017-10-14T03:43:48.000Z"
          }
        ],
        "totals" => {
          "items" => "39.99",
          "freight" => "9.52",
          "order" => "49.51",
          "paid" => "49.51"
        }
      },
      response.parsed_body
    )
  end

  test "returns empty reviews and nullable timestamps" do
    get "/api/orders/#{@order_two.order_id}"

    assert_response :success
    assert_equal [], response.parsed_body["reviews"]
    assert_nil response.parsed_body["approved_at"]
    assert_nil response.parsed_body["delivered_carrier_at"]
    assert_nil response.parsed_body["delivered_customer_at"]
    assert_equal({ "items" => "0.00", "freight" => "0.00", "order" => "0.00", "paid" => "0.00" }, response.parsed_body["totals"])
  end

  test "returns exact not found response for an unknown external id" do
    get "/api/orders/unknown-order-id"

    assert_response :not_found
    assert_equal({ "error" => "order_not_found" }, response.parsed_body)
  end

  test "does not look up orders by internal database id" do
    get "/api/orders/#{@order_one.id}"

    assert_response :not_found
    assert_equal({ "error" => "order_not_found" }, response.parsed_body)
  end
end
