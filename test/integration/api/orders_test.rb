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

    test "lists every delivery classification with equality on time and the public timestamp contract" do
      create_order(
        order_id: "order-index-pending-0001",
        delivered_customer_at: nil
      )
      create_order(
        order_id: "order-index-on-time-0001",
        delivered_customer_at: Time.utc(2024, 1, 12)
      )
      create_order(
        order_id: "order-index-late-0001",
        delivered_customer_at: Time.utc(2024, 1, 12, 0, 0, 1)
      )

      get "/api/orders"

      assert_response :ok
      body = response.parsed_body
      assert_equal({ "page" => 1, "per_page" => 25, "total_orders" => 3, "total_pages" => 1 }, body.except("orders"))

      orders = body.fetch("orders").index_by { |order| order.fetch("order_id") }
      assert_equal %w[late on_time pending], orders.values.pluck("delivery_status").sort
      assert_equal "pending", orders.fetch("order-index-pending-0001").fetch("delivery_status")
      assert_equal "on_time", orders.fetch("order-index-on-time-0001").fetch("delivery_status")
      assert_equal "late", orders.fetch("order-index-late-0001").fetch("delivery_status")
      assert_nil orders.fetch("order-index-pending-0001").fetch("delivered_customer_at")
      assert_equal "2024-01-02T03:04:05.000Z", orders.fetch("order-index-on-time-0001").fetch("purchase_at")
      assert_equal "2024-01-12T00:00:00.000Z", orders.fetch("order-index-on-time-0001").fetch("estimated_delivery_at")
      assert_equal "2024-01-12T00:00:00.000Z", orders.fetch("order-index-on-time-0001").fetch("delivered_customer_at")
      orders.each_value do |order|
        assert_equal %w[delivered_customer_at delivery_status estimated_delivery_at order_id purchase_at status], order.keys.sort
        refute order.key?("id")
      end
    end

    test "filters each delivery status in the database before instantiating records" do
      create_order(order_id: "order-filter-pending-0001", delivered_customer_at: nil)
      create_order(order_id: "order-filter-on-time-0001", delivered_customer_at: Time.utc(2024, 1, 11))
      create_order(order_id: "order-filter-late-0001", delivered_customer_at: Time.utc(2024, 1, 13))

      {
        "pending" => "order-filter-pending-0001",
        "on_time" => "order-filter-on-time-0001",
        "late" => "order-filter-late-0001"
      }.each do |delivery_status, expected_order_id|
        instantiated_orders = count_instantiated_orders do
          get "/api/orders", params: { delivery_status:, per_page: "100" }
        end

        assert_response :ok
        body = response.parsed_body
        assert_equal [ expected_order_id ], body.fetch("orders").pluck("order_id")
        assert_equal [ delivery_status ], body.fetch("orders").pluck("delivery_status")
        assert_equal 1, instantiated_orders, "expected #{delivery_status.inspect} filtering to happen before record instantiation"
      end
    end

    test "rejects unsupported and structured delivery statuses with the exact error" do
      [ "delivery_status=in_transit", "delivery_status[]=pending" ].each do |query|
        get "/api/orders?#{query}"

        assert_response :unprocessable_entity, "expected #{query.inspect} to be rejected"
        assert_equal({ "error" => "invalid_delivery_status" }, response.parsed_body)
      end
    end

    test "defaults to page one with 25 records and reports the complete result metadata" do
      26.times do |index|
        create_order(
          order_id: format("order-default-page-%04d", index),
          delivered_customer_at: nil
        )
      end

      get "/api/orders"

      assert_response :ok
      body = response.parsed_body
      assert_equal 25, body.fetch("orders").length
      assert_equal({ "page" => 1, "per_page" => 25, "total_orders" => 26, "total_pages" => 2 }, body.except("orders"))
    end

    test "accepts the maximum page size and rejects invalid pagination values" do
      create_order(order_id: "order-pagination-0001", delivered_customer_at: nil)

      get "/api/orders", params: { page: "1", per_page: "100" }

      assert_response :ok
      assert_equal({ "page" => 1, "per_page" => 100 }, response.parsed_body.slice("page", "per_page"))

      invalid_queries = [
        "page=0", "page=-1", "page=abc", "page=1.0", "page=01", "page=%2B1", "page=%201", "page=", "page[]=1",
        "per_page=0", "per_page=-1", "per_page=abc", "per_page=1.0", "per_page=01", "per_page=101", "per_page[]=25"
      ]

      invalid_queries.each do |query|
        get "/api/orders?#{query}"

        assert_response :unprocessable_entity, "expected #{query.inspect} to be rejected"
        assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
      end
    end

    test "paginates filtered ties deterministically and returns an empty valid far page" do
      purchase_at = Time.utc(2024, 6, 1, 12)
      %w[c a b].each do |suffix|
        create_order(
          order_id: "order-filtered-tie-#{suffix}",
          purchase_at:,
          delivered_customer_at: Time.utc(2024, 1, 13)
        )
      end
      create_order(
        order_id: "order-filtered-nonmatch",
        purchase_at:,
        delivered_customer_at: nil
      )

      get "/api/orders", params: { delivery_status: "late", page: "1", per_page: "2" }

      assert_response :ok
      body = response.parsed_body
      assert_equal %w[order-filtered-tie-a order-filtered-tie-b], body.fetch("orders").pluck("order_id")
      assert_equal({ "page" => 1, "per_page" => 2, "total_orders" => 3, "total_pages" => 2 }, body.except("orders"))

      get "/api/orders", params: { delivery_status: "late", page: "2", per_page: "2" }

      assert_response :ok
      assert_equal [ "order-filtered-tie-c" ], response.parsed_body.fetch("orders").pluck("order_id")

      get "/api/orders", params: { delivery_status: "late", page: "999999999999999999999999999999999", per_page: "2" }

      assert_response :ok
      assert_equal [], response.parsed_body.fetch("orders")
      assert_equal({ "total_orders" => 3, "total_pages" => 2 }, response.parsed_body.slice("total_orders", "total_pages"))
    end

    private

    def create_order(order_id:, approved_at: Time.utc(2024, 1, 2, 4, 5, 6), delivered_carrier_at: Time.utc(2024, 1, 4), delivered_customer_at: Time.utc(2024, 1, 8), purchase_at: Time.utc(2024, 1, 2, 3, 4, 5))
      Order.create!(
        order_id:,
        customer: @customer,
        status: "delivered",
        purchase_at:,
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

    def count_instantiated_orders
      count = 0
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        count += payload[:record_count] if payload[:class_name] == "Order"
      end

      ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") { yield }
      count
    end
  end
end
