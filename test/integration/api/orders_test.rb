require "test_helper"

module Api
  class OrdersTest < ActionDispatch::IntegrationTest
    self.fixture_table_names = []

    test "lists every delivery classification with the exact public contract and default pagination" do
      customer = create_customer
      purchase_at = Time.utc(2017, 10, 2, 10, 56, 33)
      estimated_at = Time.utc(2017, 10, 18)
      create_order(
        customer: customer,
        order_id: "pending-order",
        purchase_at: purchase_at + 3.minutes,
        estimated_delivery_at: estimated_at,
        delivered_customer_at: nil
      )
      create_order(
        customer: customer,
        order_id: "on-time-at-boundary",
        purchase_at: purchase_at + 2.minutes,
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at
      )
      create_order(
        customer: customer,
        order_id: "on-time-before-boundary",
        purchase_at: purchase_at + 1.minute,
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at - 1.second
      )
      create_order(
        customer: customer,
        order_id: "late-order",
        purchase_at: purchase_at,
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at + 1.second
      )

      get "/api/orders"

      assert_response :ok
      assert_equal "application/json", response.media_type
      body = response.parsed_body
      assert_equal %w[orders page per_page total_orders total_pages], body.keys.sort
      assert_equal 1, body["page"]
      assert_equal 25, body["per_page"]
      assert_equal 4, body["total_orders"]
      assert_equal 1, body["total_pages"]
      assert_equal(
        %w[pending-order on-time-at-boundary on-time-before-boundary late-order],
        body.fetch("orders").pluck("order_id")
      )

      orders_by_id = body.fetch("orders").index_by { |order| order.fetch("order_id") }
      assert_equal "pending", orders_by_id.fetch("pending-order").fetch("delivery_status")
      assert_nil orders_by_id.fetch("pending-order")["delivered_customer_at"]
      assert_equal "on_time", orders_by_id.fetch("on-time-at-boundary").fetch("delivery_status")
      assert_equal "on_time", orders_by_id.fetch("on-time-before-boundary").fetch("delivery_status")
      assert_equal "late", orders_by_id.fetch("late-order").fetch("delivery_status")

      orders_by_id.each_value do |order|
        assert_equal %w[
          delivered_customer_at delivery_status estimated_delivery_at order_id purchase_at status
        ], order.keys.sort
      end
      assert_equal "2017-10-18T00:00:00.000Z",
        orders_by_id.fetch("on-time-at-boundary").fetch("estimated_delivery_at")
      assert_equal "2017-10-18T00:00:00.000Z",
        orders_by_id.fetch("on-time-at-boundary").fetch("delivered_customer_at")
    end

    test "filters each classification and calculates metadata from only matching orders" do
      customer = create_customer
      estimated_at = Time.utc(2017, 10, 18)
      classifications = {
        "pending" => [ nil, nil ],
        "on_time" => [ estimated_at - 1.second, estimated_at ],
        "late" => [ estimated_at + 1.second, estimated_at + 1.day ]
      }

      classifications.each do |status, delivered_times|
        delivered_times.each_with_index do |delivered_at, index|
          create_order(
            customer: customer,
            order_id: "#{status}-#{index}",
            purchase_at: Time.utc(2017, 10, 2) + index.minutes,
            estimated_delivery_at: estimated_at,
            delivered_customer_at: delivered_at
          )
        end
      end

      classifications.each_key do |status|
        get "/api/orders", params: { delivery_status: status, page: 2, per_page: 1 }

        assert_response :ok
        body = response.parsed_body
        assert_equal 2, body["page"]
        assert_equal 1, body["per_page"]
        assert_equal 2, body["total_orders"]
        assert_equal 2, body["total_pages"]
        assert_equal [ status ], body.fetch("orders").pluck("delivery_status").uniq
        assert_equal [ "#{status}-0" ], body.fetch("orders").pluck("order_id")
      end
    end

    test "applies delivery status filtering in SQL" do
      create_order(customer: create_customer, order_id: "pending-order", delivered_customer_at: nil)

      statements = capture_select_sql do
        get "/api/orders", params: { delivery_status: "pending" }
      end

      assert_response :ok
      order_queries = statements.grep(/FROM "orders"/)
      assert_operator order_queries.size, :>=, 2
      assert order_queries.all? { |sql| sql.match?(/"orders"\."delivered_customer_at" IS NULL/) },
        "expected count and page queries to filter delivered_customer_at in SQL: #{order_queries.inspect}"
    end

    test "rejects unsupported scalar and structured delivery statuses" do
      [ "unknown", "", [ "pending" ], { value: "pending" } ].each do |delivery_status|
        get "/api/orders", params: { delivery_status: delivery_status }

        assert_response :unprocessable_content
        assert_equal({ "error" => "invalid_delivery_status" }, response.parsed_body)
        assert_equal [ "error" ], response.parsed_body.keys
      end
    end

    test "paginates deterministically and accepts the maximum page size" do
      customer = create_customer
      purchase_at = Time.utc(2017, 10, 2)
      create_order(customer: customer, order_id: "order-b", purchase_at: purchase_at)
      create_order(customer: customer, order_id: "order-a", purchase_at: purchase_at)
      create_order(customer: customer, order_id: "order-newest", purchase_at: purchase_at + 1.minute)

      get "/api/orders", params: { page: 1, per_page: 2 }
      first_page = response.parsed_body
      get "/api/orders", params: { page: 2, per_page: 2 }
      second_page = response.parsed_body
      get "/api/orders", params: { page: 2, per_page: 100 }
      maximum_page = response.parsed_body

      assert_equal %w[order-newest order-a], first_page.fetch("orders").pluck("order_id")
      assert_equal [ "order-b" ], second_page.fetch("orders").pluck("order_id")
      assert_equal 3, second_page["total_orders"]
      assert_equal 2, second_page["total_pages"]
      assert_equal 2, maximum_page["page"]
      assert_equal 100, maximum_page["per_page"]
      assert_equal 1, maximum_page["total_pages"]
      assert_equal [], maximum_page["orders"]
    end

    test "rejects malformed pagination and page sizes above the maximum" do
      invalid_parameters = [
        { page: "0" },
        { page: "-1" },
        { page: "abc" },
        { page: "1.5" },
        { page: " 1" },
        { page: [ "1" ] },
        { per_page: "0" },
        { per_page: "-1" },
        { per_page: "101" },
        { per_page: "abc" },
        { per_page: { value: "25" } }
      ]

      invalid_parameters.each do |parameters|
        get "/api/orders", params: parameters

        assert_response :unprocessable_content, "expected #{parameters.inspect} to be rejected"
        assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
      end
    end

    test "returns zero filtered totals for an empty result set" do
      create_order(customer: create_customer, order_id: "pending-order", delivered_customer_at: nil)

      get "/api/orders", params: { delivery_status: "late" }

      assert_response :ok
      assert_equal 0, response.parsed_body["total_orders"]
      assert_equal 0, response.parsed_body["total_pages"]
      assert_equal [], response.parsed_body["orders"]
    end

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

    def capture_select_sql
      ActiveRecord::Base.connection.clear_query_cache
      statements = []
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]
        next unless payload[:sql].match?(/\ASELECT\b/i)

        statements << payload[:sql]
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
      statements
    end

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
