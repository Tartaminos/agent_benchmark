require "test_helper"

module Admin
  class OrdersTest < ActionDispatch::IntegrationTest
    self.fixture_table_names = []

    setup do
      @product = Product.create!(product_id: "admin-product-00000000000000001")
      @seller = Seller.create!(
        seller_id: "admin-seller-000000000000000001",
        zip_code_prefix: "01001",
        city: "sao paulo",
        state: "SP"
      )
      @sequence = 0
    end

    test "routes the dashboard and paginates equal timestamps deterministically with newest first" do
      older = create_order(order_id: external_id("older"), purchase_at: Time.utc(2024, 1, 1))
      tied = 11.times.map do |index|
        create_order(order_id: format("admin-tie-order-%016d", index), purchase_at: Time.utc(2024, 2, 1))
      end

      get admin_orders_path

      assert_response :ok
      assert_select "h1", text: "Orders"
      assert_select "tbody tr", count: 10
      assert_select "tbody tr:first-child .order-id", text: tied.first.order_id
      assert_select "tbody", { text: /#{Regexp.escape(tied.last.order_id)}/, count: 0 }
      assert_select "tbody", { text: /#{Regexp.escape(older.order_id)}/, count: 0 }

      next_href = nil
      assert_select "a[aria-label='Next page']" do |links|
        next_href = links.first["href"]
      end
      assert_includes next_href, "page=2"
      assert_includes next_href, "sort=desc"
      assert_includes next_href, "per_page=10"

      get next_href

      assert_response :ok
      assert_select "tbody", text: /#{Regexp.escape(tied.last.order_id)}/
      assert_select "tbody", text: /#{Regexp.escape(older.order_id)}/
      assert_select ".pagination [aria-current='page']", text: "2"
    end

    test "combines external id, order status, derived delivery, customer state, and inclusive date filters" do
      target = create_order(
        order_id: "admin-combined-target-000000001",
        status: "delivered",
        state: "SP",
        purchase_at: Time.utc(2024, 3, 31, 23, 59, 59),
        estimated_delivery_at: Time.utc(2024, 4, 5),
        delivered_customer_at: Time.utc(2024, 4, 5, 0, 0, 1)
      )
      create_order(order_id: "admin-combined-wrong-status-001", status: "shipped", state: "SP", purchase_at: target.purchase_at, delivered_customer_at: Time.utc(2024, 4, 6))
      create_order(order_id: "admin-combined-wrong-state-0001", status: "delivered", state: "RJ", purchase_at: target.purchase_at, delivered_customer_at: Time.utc(2024, 4, 6))
      create_order(order_id: "admin-combined-wrong-date-00001", status: "delivered", state: "SP", purchase_at: Time.utc(2024, 4, 1), delivered_customer_at: Time.utc(2024, 4, 6))
      create_order(order_id: "admin-combined-pending-0000001", status: "delivered", state: "SP", purchase_at: target.purchase_at, delivered_customer_at: nil)
      equality = create_order(order_id: "admin-delivery-equality-00000001", estimated_delivery_at: Time.utc(2024, 4, 5), delivered_customer_at: Time.utc(2024, 4, 5))

      get admin_orders_path, params: {
        order_id: "TARGET",
        order_status: "delivered",
        delivery_status: "late",
        customer_state: "SP",
        purchase_from: "2024-03-31",
        purchase_to: "2024-03-31"
      }

      assert_response :ok
      assert_select "tbody tr", count: 1
      assert_select ".order-id", text: target.order_id
      assert_select "tbody", { text: /Pending/, count: 0 }
      assert_select "tbody", text: /Late/

      get admin_orders_path, params: { delivery_status: "on_time", order_id: "equality" }

      assert_response :ok
      assert_select ".order-id", text: equality.order_id
      assert_select "tbody", text: /On time/
    end

    test "preserves every active filter while sorting and paging and clear filters removes them" do
      11.times do |index|
        create_order(
          order_id: format("admin-preserved-%016d", index),
          status: "delivered",
          state: "SP",
          purchase_at: Time.utc(2024, 5, index + 1),
          estimated_delivery_at: Time.utc(2024, 6, 1),
          delivered_customer_at: nil
        )
      end
      create_order(order_id: external_id("excluded"), status: "canceled", state: "RJ")

      filters = {
        order_id: "admin-preserved",
        order_status: "delivered",
        delivery_status: "pending",
        customer_state: "SP",
        purchase_from: "2024-05-01",
        purchase_to: "2024-05-31",
        sort: "asc",
        per_page: "10"
      }
      get admin_orders_path, params: filters

      assert_response :ok
      assert_select "tbody tr:first-child .order-id", text: format("admin-preserved-%016d", 0)
      assert_select "form.sort-form input[name='order_id'][value='admin-preserved']"
      assert_select "form.sort-form input[name='order_status'][value='delivered']"
      assert_select "form.sort-form input[name='delivery_status'][value='pending']"
      assert_select "form.sort-form input[name='customer_state'][value='SP']"
      assert_select "form.sort-form input[name='purchase_from'][value='2024-05-01']"
      assert_select "form.sort-form input[name='purchase_to'][value='2024-05-31']"
      assert_select "select[name='sort'] option[value='asc'][selected]"

      assert_select "a[aria-label='Next page']" do |links|
        query = Rack::Utils.parse_nested_query(URI.parse(links.first["href"]).query)
        assert_equal filters.merge(page: "2").stringify_keys, query
      end
      assert_select "a", text: "Clear filters" do |links|
        assert links.any? { |link| URI.parse(link["href"]).query.nil? }
      end
    end

    test "renders exact list and detail totals without payment or item fan-out and exposes only external identifiers" do
      order = create_order(order_id: "external-order-visible-000000001", customer_id: "external-customer-visible-00001", unique_id: "external-shopper-visible-000001")
      create_item(order:, position: 1, price: "10.10", freight: "2.20")
      create_item(order:, position: 2, price: "0.30", freight: "4.40")
      create_payment(order:, sequence: 1, value: "7.00")
      create_payment(order:, sequence: 2, value: "10.00")

      get admin_orders_path, params: { order_id: order.order_id }

      assert_response :ok
      assert_select "tbody tr", count: 1
      assert_select "tbody .money", text: "R$ 17,00"
      assert_select "a[aria-label='View order #{order.order_id}']" do |links|
        assert_includes links.first["href"], "/admin/orders/#{order.order_id}"
        refute_includes links.first["href"], "/admin/orders/#{order.id}?"
      end

      get admin_order_path(order.order_id)

      assert_response :ok
      assert_select ".order-detail", text: /#{Regexp.escape(order.order_id)}/
      assert_select ".order-detail", text: /external-customer-visible-00001/
      assert_select ".order-detail", text: /external-shopper-visible-000001/
      assert_detail_value "Items total", "R$ 10,40"
      assert_detail_value "Freight total", "R$ 6,60"
      assert_detail_value "Order total", "R$ 17,00"
      assert_detail_value "Paid total", "R$ 17,00"
      refute_match %r{/admin/orders/#{order.id}(?:\?|"|$)}, response.body
    end

    test "renders explicit no-results, invalid-filter, and missing-detail states" do
      create_order(order_id: external_id("available"))

      get admin_orders_path, params: { order_id: "does-not-exist" }
      assert_response :ok
      assert_select "[role='status'] h3", text: "No orders match these filters."

      get admin_orders_path, params: { delivery_status: "in_transit", purchase_from: "not-a-date" }
      assert_response :ok
      assert_select "[role='alert']", text: /Delivery status is not valid\./
      assert_select "[role='alert']", text: /Purchase date from is not a valid date\./
      assert_select "tbody tr", count: 0

      get admin_order_path("missing-external-order")
      assert_response :not_found
      assert_select "[role='alert'] h3", text: "Order details are unavailable."
      assert_select "a", text: "Back to orders"
    end

    test "listing query count stays bounded as the page fills" do
      10.times do |index|
        order = create_order(order_id: format("admin-query-count-%014d", index))
        create_item(order:, position: 1, price: "1.00", freight: "0.50")
      end

      sql = capture_selects { get admin_orders_path }

      assert_response :ok
      assert_operator sql.length, :<=, 5, "expected statuses, states, count, page, and one page-total query; got:\n#{sql.join("\n")}" 
      assert_equal 1, sql.count { |statement| statement.match?(/FROM \"order_items\"/) }
      assert_equal 1, sql.count { |statement| statement.match?(/FROM \"orders\"/) && statement.match?(/LIMIT/) }
    end

    private

    def external_id(label)
      @sequence += 1
      "admin-#{label}-#{format('%012d', @sequence)}".first(32)
    end

    def create_order(order_id:, status: "delivered", state: "SP", purchase_at: Time.utc(2024, 2, 1), estimated_delivery_at: Time.utc(2024, 2, 10), delivered_customer_at: Time.utc(2024, 2, 9), customer_id: nil, unique_id: nil)
      @sequence += 1
      customer = Customer.create!(
        customer_id: customer_id || format("admin-customer-%014d", @sequence),
        customer_unique_id: unique_id || format("admin-shopper-%015d", @sequence),
        zip_code_prefix: "01001",
        city: "sao paulo",
        state:
      )
      Order.create!(order_id:, customer:, status:, purchase_at:, estimated_delivery_at:, delivered_customer_at:)
    end

    def create_item(order:, position:, price:, freight:)
      OrderItem.create!(
        order:,
        product: @product,
        seller: @seller,
        order_item_id: position,
        shipping_limit_at: Time.utc(2024, 2, 3),
        price:,
        freight_value: freight
      )
    end

    def create_payment(order:, sequence:, value:)
      OrderPayment.create!(
        order:,
        payment_sequential: sequence,
        payment_type: "credit_card",
        payment_installments: 1,
        payment_value: value
      )
    end

    def assert_detail_value(label, value)
      assert_select ".detail-card dl div" do |rows|
        row = rows.find { |candidate| candidate.at_css("dt")&.text == label }
        assert row, "expected detail row #{label.inspect}"
        assert_equal value, row.at_css("dd").text.strip
      end
    end

    def capture_selects(&block)
      statements = []
      callback = lambda do |*, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]
        statements << payload[:sql] if payload[:sql].start_with?("SELECT")
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
      statements
    end
  end
end
