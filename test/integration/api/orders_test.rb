require "test_helper"

module Api
  class OrdersTest < ActionDispatch::IntegrationTest
    self.fixture_table_names = []

    test "returns the complete order contract by external order id" do
      customer = create_customer(
        customer_id: "customer-public-id",
        customer_unique_id: "customer-unique-id",
        city: "sao paulo",
        state: "SP"
      )
      order = create_order(
        customer: customer,
        order_id: "external-order-id",
        approved_at: nil,
        delivered_carrier_at: Time.utc(2017, 10, 4, 19, 55),
        delivered_customer_at: nil
      )
      first_product = create_product(product_id: "first-product-id")
      second_product = create_product(product_id: "second-product-id")
      first_seller = create_seller(seller_id: "first-seller-id")
      second_seller = create_seller(seller_id: "second-seller-id")

      create_item(
        order: order,
        product: second_product,
        seller: second_seller,
        order_item_id: 2,
        price: "20.00",
        freight_value: "0.08"
      )
      create_item(
        order: order,
        product: first_product,
        seller: first_seller,
        order_item_id: 1,
        price: "9.90",
        freight_value: "1.02"
      )
      create_payment(
        order: order,
        payment_sequential: 2,
        payment_type: "voucher",
        payment_installments: 1,
        payment_value: "0.10"
      )
      create_payment(
        order: order,
        payment_sequential: 1,
        payment_type: "credit_card",
        payment_installments: 2,
        payment_value: "30.90"
      )
      create_review(
        order: order,
        review_id: "second-review-id",
        score: 3,
        comment_title: "Second review",
        comment_message: "Delivered"
      )
      create_review(
        order: order,
        review_id: "first-review-id",
        score: 5,
        comment_title: nil,
        comment_message: nil
      )

      get "/api/orders/#{order.order_id}"

      assert_response :ok
      assert_equal "application/json", response.media_type

      body = response.parsed_body
      assert_equal %w[
        approved_at customer delivered_carrier_at delivered_customer_at
        estimated_delivery_at items order_id payments purchase_at reviews status totals
      ], body.keys.sort
      assert_equal "external-order-id", body["order_id"]
      refute_equal order.id.to_s, body["order_id"]
      assert_equal "delivered", body["status"]
      assert_equal "2017-10-02T10:56:33.000Z", body["purchase_at"]
      assert_nil body["approved_at"]
      assert_equal "2017-10-04T19:55:00.000Z", body["delivered_carrier_at"]
      assert_nil body["delivered_customer_at"]
      assert_equal "2017-10-18T00:00:00.000Z", body["estimated_delivery_at"]

      assert_equal %w[city customer_id customer_unique_id state], body.fetch("customer").keys.sort
      assert_equal(
        {
          "customer_id" => "customer-public-id",
          "customer_unique_id" => "customer-unique-id",
          "city" => "sao paulo",
          "state" => "SP"
        },
        body["customer"]
      )

      assert_equal [ 1, 2 ], body.fetch("items").pluck("order_item_id")
      assert_equal(
        [
          {
            "order_item_id" => 1,
            "product_id" => "first-product-id",
            "seller_id" => "first-seller-id",
            "price" => "9.90",
            "freight_value" => "1.02"
          },
          {
            "order_item_id" => 2,
            "product_id" => "second-product-id",
            "seller_id" => "second-seller-id",
            "price" => "20.00",
            "freight_value" => "0.08"
          }
        ],
        body["items"]
      )

      assert_equal [ 1, 2 ], body.fetch("payments").pluck("payment_sequential")
      assert_equal(
        [
          {
            "payment_sequential" => 1,
            "payment_type" => "credit_card",
            "payment_installments" => 2,
            "payment_value" => "30.90"
          },
          {
            "payment_sequential" => 2,
            "payment_type" => "voucher",
            "payment_installments" => 1,
            "payment_value" => "0.10"
          }
        ],
        body["payments"]
      )

      assert_equal 2, body.fetch("reviews").size
      reviews_by_id = body["reviews"].index_by { |review| review.fetch("review_id") }
      assert_equal %w[first-review-id second-review-id], reviews_by_id.keys.sort
      assert_equal(
        {
          "review_id" => "first-review-id",
          "score" => 5,
          "comment_title" => nil,
          "comment_message" => nil,
          "creation_at" => "2017-10-11T00:00:00.000Z",
          "answer_at" => "2017-10-12T03:43:48.000Z"
        },
        reviews_by_id["first-review-id"]
      )
      assert_equal(
        {
          "review_id" => "second-review-id",
          "score" => 3,
          "comment_title" => "Second review",
          "comment_message" => "Delivered",
          "creation_at" => "2017-10-11T00:00:00.000Z",
          "answer_at" => "2017-10-12T03:43:48.000Z"
        },
        reviews_by_id["second-review-id"]
      )
      assert_equal(
        { "items" => "29.90", "freight" => "1.10", "order" => "31.00", "paid" => "31.00" },
        body["totals"]
      )
    end

    test "returns empty reviews and zero totals when an order has no related rows" do
      order = create_order(customer: create_customer, order_id: "empty-order-id")

      get "/api/orders/#{order.order_id}"

      assert_response :ok
      body = response.parsed_body
      assert_equal [], body["items"]
      assert_equal [], body["payments"]
      assert_equal [], body["reviews"]
      assert_equal(
        { "items" => "0.00", "freight" => "0.00", "order" => "0.00", "paid" => "0.00" },
        body["totals"]
      )
    end

    test "returns the exact not-found contract for an unknown external order id" do
      get "/api/orders/unknown-external-order-id"

      assert_response :not_found
      assert_equal "application/json", response.media_type
      assert_equal({ "error" => "order_not_found" }, response.parsed_body)
      assert_equal [ "error" ], response.parsed_body.keys
    end

    private

    def create_customer(attributes = {})
      Customer.create!({
        customer_id: "default-customer-id",
        customer_unique_id: "default-unique-id",
        zip_code_prefix: "01001",
        city: "curitiba",
        state: "PR"
      }.merge(attributes))
    end

    def create_order(customer:, order_id:, **attributes)
      Order.create!({
        customer: customer,
        order_id: order_id,
        status: "delivered",
        purchase_at: Time.utc(2017, 10, 2, 10, 56, 33),
        approved_at: Time.utc(2017, 10, 2, 11, 7, 15),
        delivered_carrier_at: Time.utc(2017, 10, 4, 19, 55),
        delivered_customer_at: Time.utc(2017, 10, 10, 21, 25, 13),
        estimated_delivery_at: Time.utc(2017, 10, 18)
      }.merge(attributes))
    end

    def create_product(product_id:)
      Product.create!(product_id: product_id)
    end

    def create_seller(seller_id:)
      Seller.create!(
        seller_id: seller_id,
        zip_code_prefix: "01001",
        city: "sao paulo",
        state: "SP"
      )
    end

    def create_item(order:, product:, seller:, **attributes)
      OrderItem.create!({
        order: order,
        product: product,
        seller: seller,
        shipping_limit_at: Time.utc(2017, 10, 6)
      }.merge(attributes))
    end

    def create_payment(order:, **attributes)
      OrderPayment.create!({ order: order }.merge(attributes))
    end

    def create_review(order:, **attributes)
      OrderReview.create!({
        order: order,
        creation_at: Time.utc(2017, 10, 11),
        answer_at: Time.utc(2017, 10, 12, 3, 43, 48)
      }.merge(attributes))
    end
  end
end
