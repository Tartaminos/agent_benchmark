require "test_helper"

module Api
  class OrdersTest < ActionDispatch::IntegrationTest
    self.fixture_table_names = []

    setup do
      @customer = Customer.create!(
        customer_id: "customer-contract-0001",
        customer_unique_id: "shopper-contract-0001",
        zip_code_prefix: "01001",
        city: "sao paulo",
        state: "SP"
      )
      @products = [
        Product.create!(product_id: "product-contract-0001"),
        Product.create!(product_id: "product-contract-0002")
      ]
      @sellers = [
        Seller.create!(seller_id: "seller-contract-0001", zip_code_prefix: "20001", city: "rio de janeiro", state: "RJ"),
        Seller.create!(seller_id: "seller-contract-0002", zip_code_prefix: "30110", city: "belo horizonte", state: "MG")
      ]
    end

    test "returns the exact public order contract with ordered collections and precise totals" do
      order = create_order(
        order_id: "order-contract-0001",
        approved_at: nil,
        delivered_carrier_at: nil,
        delivered_customer_at: nil
      )

      create_item(order:, position: 2, product: @products.second, seller: @sellers.second, price: "0.10", freight: "2.30")
      create_item(order:, position: 1, product: @products.first, seller: @sellers.first, price: "10.00", freight: "0.00")
      create_payment(order:, sequence: 2, type: "voucher", installments: 1, value: "7.40")
      create_payment(order:, sequence: 1, type: "credit_card", installments: 2, value: "5.00")
      create_review(
        order:,
        review_id: "review-contract-0002",
        score: 3,
        title: "acceptable",
        message: "arrived",
        creation_at: Time.utc(2024, 2, 4, 5, 6, 7),
        answer_at: Time.utc(2024, 2, 5, 6, 7, 8)
      )
      create_review(
        order:,
        review_id: "review-contract-0001",
        score: 5,
        title: nil,
        message: nil,
        creation_at: Time.utc(2024, 2, 2, 3, 4, 5),
        answer_at: Time.utc(2024, 2, 3, 4, 5, 6)
      )

      get "/api/orders/#{order.order_id}"

      assert_response :ok
      body = response.parsed_body
      assert_equal %w[approved_at customer delivered_carrier_at delivered_customer_at estimated_delivery_at items order_id payments purchase_at reviews status totals], body.keys.sort
      assert_equal order.order_id, body["order_id"]
      assert_equal "delivered", body["status"]
      assert_equal "2024-01-02T03:04:05.000Z", body["purchase_at"]
      assert_nil body["approved_at"]
      assert_nil body["delivered_carrier_at"]
      assert_nil body["delivered_customer_at"]
      assert_equal "2024-01-12T00:00:00.000Z", body["estimated_delivery_at"]
      assert_equal(
        {
          "customer_id" => "customer-contract-0001",
          "customer_unique_id" => "shopper-contract-0001",
          "city" => "sao paulo",
          "state" => "SP"
        },
        body["customer"]
      )
      assert_equal(
        [
          {
            "order_item_id" => 1,
            "product_id" => "product-contract-0001",
            "seller_id" => "seller-contract-0001",
            "price" => "10.00",
            "freight_value" => "0.00"
          },
          {
            "order_item_id" => 2,
            "product_id" => "product-contract-0002",
            "seller_id" => "seller-contract-0002",
            "price" => "0.10",
            "freight_value" => "2.30"
          }
        ],
        body["items"]
      )
      assert_equal(
        [
          {
            "payment_sequential" => 1,
            "payment_type" => "credit_card",
            "payment_installments" => 2,
            "payment_value" => "5.00"
          },
          {
            "payment_sequential" => 2,
            "payment_type" => "voucher",
            "payment_installments" => 1,
            "payment_value" => "7.40"
          }
        ],
        body["payments"]
      )
      assert_equal(
        {
          "review-contract-0001" => {
            "review_id" => "review-contract-0001",
            "score" => 5,
            "comment_title" => nil,
            "comment_message" => nil,
            "creation_at" => "2024-02-02T03:04:05.000Z",
            "answer_at" => "2024-02-03T04:05:06.000Z"
          },
          "review-contract-0002" => {
            "review_id" => "review-contract-0002",
            "score" => 3,
            "comment_title" => "acceptable",
            "comment_message" => "arrived",
            "creation_at" => "2024-02-04T05:06:07.000Z",
            "answer_at" => "2024-02-05T06:07:08.000Z"
          }
        },
        body.fetch("reviews").index_by { |review| review.fetch("review_id") }
      )
      assert_equal 2, body["reviews"].length
      assert_equal(
        { "items" => "10.10", "freight" => "2.30", "order" => "12.40", "paid" => "12.40" },
        body["totals"]
      )
    end

    test "returns an empty reviews array when the order has no reviews" do
      order = create_order(order_id: "order-without-reviews-0001")

      get "/api/orders/#{order.order_id}"

      assert_response :ok
      assert_equal [], response.parsed_body["reviews"]
    end

    test "returns the exact not found response for an unknown external order id" do
      get "/api/orders/order-that-does-not-exist"

      assert_response :not_found
      assert_equal({ "error" => "order_not_found" }, response.parsed_body)
    end

    private

    def create_order(order_id:, approved_at: Time.utc(2024, 1, 2, 4, 5, 6), delivered_carrier_at: Time.utc(2024, 1, 4), delivered_customer_at: Time.utc(2024, 1, 8))
      Order.create!(
        order_id:,
        customer: @customer,
        status: "delivered",
        purchase_at: Time.utc(2024, 1, 2, 3, 4, 5),
        approved_at:,
        delivered_carrier_at:,
        delivered_customer_at:,
        estimated_delivery_at: Time.utc(2024, 1, 12)
      )
    end

    def create_item(order:, position:, product:, seller:, price:, freight:)
      OrderItem.create!(
        order:,
        product:,
        seller:,
        order_item_id: position,
        shipping_limit_at: Time.utc(2024, 1, 3),
        price:,
        freight_value: freight
      )
    end

    def create_payment(order:, sequence:, type:, installments:, value:)
      OrderPayment.create!(
        order:,
        payment_sequential: sequence,
        payment_type: type,
        payment_installments: installments,
        payment_value: value
      )
    end

    def create_review(order:, review_id:, score:, title:, message:, creation_at:, answer_at:)
      OrderReview.create!(
        order:,
        review_id:,
        score:,
        comment_title: title,
        comment_message: message,
        creation_at:,
        answer_at:
      )
    end
  end
end
