require "test_helper"
require "uri"

module Admin
  class OrdersDashboardTest < ActionDispatch::IntegrationTest
    self.fixture_table_names = []

    setup { @record_sequence = 0 }

    test "renders a semantic paginated dashboard ordered newest first without exposing database ids" do
      customer = create_customer
      oldest = create_order(
        id: 900_001,
        customer: customer,
        order_id: "external-oldest-order",
        purchase_at: Time.utc(2017, 10, 1)
      )
      create_item(order: oldest, order_item_id: 1, price: "10.00", freight_value: "2.34")

      11.times do |index|
        create_order(
          customer: customer,
          order_id: format("external-order-%02d", index),
          purchase_at: Time.utc(2017, 10, 2) + index.days
        )
      end

      get admin_orders_path

      assert_response :ok
      assert_select "h1", text: "Orders"
      assert_select ".admin-orders__brand", text: /Olist Admin/
      assert_select "a.admin-orders__brand", count: 0
      assert_select "nav[aria-label='Primary navigation'] [aria-current=page]", text: /Orders/
      assert_select "nav[aria-label='Primary navigation'] a[aria-current=page]", count: 0
      assert_select "form label[for=order_id]", text: "Order ID"
      assert_select "form label[for=status]", text: "Order status"
      assert_select "form label[for=delivery_status]", text: "Delivery status"
      assert_select "form label[for=customer_state]", text: "Customer state"
      sort_select_id = nil
      assert_select "select[name=sort]#purchase-sort", count: 1 do |sort_selects|
        sort_select_id = sort_selects.first["id"]
      end
      assert_select "label[for='#{sort_select_id}']", text: "Purchase date", count: 1
      assert_select "fieldset legend", text: "Purchase date range"
      assert_select "input[type=submit][data-turbo-submits-with='Applying…']", count: 2
      assert_select "table caption", text: "Orders matching the current filters"
      assert_select "thead th.admin-orders__actions", text: "Actions"
      assert_select "tbody tr", count: 10
      assert_select "tbody tr:first-child th[scope=row]", text: "external-order-10"
      assert_select "nav[aria-label='Orders pagination'] a[rel=next]", text: "Next"
      assert_select "a[aria-label='View details for order external-order-10']", text: "View details", count: 1
      duplicate_ids = css_select("[id]").map { |element| element["id"] }.tally.select { |_id, count| count > 1 }
      assert_empty duplicate_ids, "expected every rendered id to be unique, found #{duplicate_ids.inspect}"
      refute_includes response.body, "900001"
    end

    test "combines exact public id, order, delivery, state, and inclusive purchase date filters" do
      matching_customer = create_customer(customer_id: "matching-customer", state: "SP")
      other_customer = create_customer(customer_id: "other-customer", state: "RJ")
      estimated_at = Time.utc(2017, 10, 20)
      target = create_order(
        customer: matching_customer,
        order_id: "exact-public-order-id",
        status: "delivered",
        purchase_at: Time.utc(2017, 10, 2),
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at
      )
      end_of_range = create_order(
        customer: matching_customer,
        order_id: "end-of-day-order",
        status: "delivered",
        purchase_at: Time.utc(2017, 10, 3, 23, 59, 59),
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at - 1.second
      )
      create_order(
        customer: other_customer,
        order_id: "wrong-state-order",
        status: "delivered",
        purchase_at: Time.utc(2017, 10, 2),
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at
      )
      create_order(
        customer: matching_customer,
        order_id: "late-order",
        status: "delivered",
        purchase_at: Time.utc(2017, 10, 2),
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at + 1.second
      )
      create_order(
        customer: matching_customer,
        order_id: "wrong-status-order",
        status: "shipped",
        purchase_at: Time.utc(2017, 10, 2, 12),
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at
      )
      create_order(
        customer: matching_customer,
        order_id: "before-range-order",
        status: "delivered",
        purchase_at: Time.utc(2017, 10, 1, 23, 59, 59),
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at
      )
      create_order(
        customer: matching_customer,
        order_id: "after-range-order",
        status: "delivered",
        purchase_at: Time.utc(2017, 10, 4),
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at
      )

      get admin_orders_path, params: {
        order_id: target.order_id,
        status: "delivered",
        delivery_status: "on_time",
        customer_state: "SP",
        start_date: "2017-10-02",
        end_date: "2017-10-03"
      }

      assert_response :ok
      assert_select "tbody tr", count: 1
      assert_select "tbody tr th[scope=row]", text: target.order_id
      assert_select ".admin-orders__badge", text: "On time"

      get admin_orders_path, params: {
        status: "delivered",
        start_date: "2017-10-02",
        end_date: "2017-10-03",
        customer_state: "SP",
        delivery_status: "on_time"
      }

      assert_response :ok
      assert_select "tbody tr th[scope=row]", text: target.order_id
      assert_select "tbody tr th[scope=row]", text: end_of_range.order_id
      assert_select "tbody tr th[scope=row]", count: 2
    end

    test "preserves active filters and ascending sort in pagination and detail navigation" do
      customer = create_customer(state: "PR")
      11.times do |index|
        create_order(
          customer: customer,
          order_id: format("filtered-order-%02d", index),
          status: "shipped",
          purchase_at: Time.utc(2017, 10, 2) + index.minutes,
          delivered_customer_at: nil
        )
      end
      params = {
        status: "shipped",
        delivery_status: "pending",
        customer_state: "PR",
        start_date: "2017-10-02",
        end_date: "2017-10-02",
        sort: "asc"
      }

      get admin_orders_path, params: params

      assert_response :ok
      assert_select "tbody tr:first-child th[scope=row]", text: "filtered-order-00"
      assert_select "nav[aria-label='Orders pagination'] a[rel=next]" do |links|
        assert_equal params.stringify_keys.merge("page" => "2"), query_params(links.first["href"])
      end
      assert_select "a[aria-label='View details for order filtered-order-00']" do |links|
        assert_equal params.stringify_keys.merge("page" => "1", "details_order_id" => "filtered-order-00"),
          query_params(links.first["href"])
        assert_equal "order-details", URI.parse(links.first["href"]).fragment
      end
      assert_select "a", text: "Clear filters" do |links|
        links.each { |link| assert_equal({ "sort" => "asc" }, query_params(link["href"])) }
      end
    end

    test "renders exact item, freight, order, and payment aggregates in external-id details" do
      customer = create_customer(
        id: 900_002,
        customer_id: "public-customer-id",
        customer_unique_id: "public-unique-id",
        city: "sao paulo",
        state: "SP"
      )
      estimated_at = Time.utc(2017, 10, 18)
      order = create_order(
        id: 900_003,
        customer: customer,
        order_id: "public-detail-order-id",
        estimated_delivery_at: estimated_at,
        delivered_customer_at: estimated_at
      )
      create_item(order: order, order_item_id: 1, price: "10.00", freight_value: "1.50")
      create_item(order: order, order_item_id: 2, price: "20.00", freight_value: "2.50")
      create_payment(order: order, payment_sequential: 1, payment_value: "12.00")
      create_payment(order: order, payment_sequential: 2, payment_value: "22.00")

      get admin_orders_path, params: { details_order_id: order.order_id }

      assert_response :ok
      assert_select "aside[aria-labelledby=order-detail-title]"
      assert_select "#order-details[tabindex='-1']"
      assert_operator response.body.index("id=\"order-details\""), :<,
        response.body.index("class=\"admin-orders__results\"")
      assert_select ".admin-orders__detail-id strong", text: order.order_id
      assert_select "#summary-title"
      assert_select ".admin-orders__detail-card", text: /On time/
      assert_select "#customer-title"
      assert_select ".admin-orders__detail-card", text: /public-customer-id/
      assert_select ".admin-orders__detail-card", text: /public-unique-id/
      assert_select "#totals-title"
      assert_select ".admin-orders__detail-card", text: /Items total\s*R\$ 30,00/
      assert_select ".admin-orders__detail-card", text: /Freight total\s*R\$ 4,00/
      assert_select ".admin-orders__detail-card", text: /Order total\s*R\$ 34,00/
      assert_select ".admin-orders__detail-card", text: /Paid total\s*R\$ 34,00/
      refute_includes response.body, "900002"
      refute_includes response.body, "900003"
    end

    test "renders explicit no-match, invalid-filter, and unavailable-detail states" do
      get admin_orders_path

      assert_response :ok
      assert_select ".admin-orders__empty h3", text: "No orders are available"

      create_order(customer: create_customer, order_id: "available-order")

      get admin_orders_path, params: { order_id: "missing-order" }

      assert_response :ok
      assert_select ".admin-orders__empty h3", text: "No orders match these filters"

      get admin_orders_path, params: {
        delivery_status: "not-a-status",
        start_date: "2017-10-03",
        end_date: "2017-10-02",
        sort: "sideways",
        page: "0",
        details_order_id: "missing-detail-order"
      }

      assert_response :ok
      assert_select "#filter-errors[role=alert]", text: /selected delivery status is invalid/i
      assert_select "[role=alert]", text: /valid purchase date range/i
      assert_select "[role=alert]", text: /sort direction is invalid/i
      assert_select "[role=alert]", text: /requested page is invalid/i
      assert_select "select[name=delivery_status][aria-invalid=true][aria-describedby=filter-errors]"
      assert_select "input[name=start_date][aria-invalid=true][aria-describedby=filter-errors]"
      assert_select "input[name=end_date][aria-invalid=true][aria-describedby=filter-errors]"
      assert_select "select[name=sort][aria-invalid=true][aria-describedby=filter-errors]"
      assert_select "h2#order-detail-title", text: "Details unavailable"
      assert_select "[role=status] h3", text: "Order details could not be found"
      assert_select "select[name=sort] option[selected][value=desc]", text: "Newest first"
    end

    test "listing query count stays fixed as a page fills and totals use one grouped aggregate" do
      customer = create_customer
      first_order = create_order(customer: customer, order_id: "query-order-00")
      create_item(order: first_order, order_item_id: 1, price: "7.11", freight_value: "2.34")

      single_order_queries = capture_select_sql { get admin_orders_path }

      9.times do |index|
        order = create_order(customer: customer, order_id: format("query-order-%02d", index + 1), purchase_at: Time.utc(2017, 10, 3) + index.minutes)
        create_item(order: order, order_item_id: 1, price: "1.00", freight_value: "0.25")
      end

      full_page_queries = capture_select_sql { get admin_orders_path }

      assert_response :ok
      assert_equal single_order_queries.size, full_page_queries.size,
        "expected a fixed query count instead of per-order customer or total queries"
      total_queries = full_page_queries.grep(/FROM "order_items"/)
      assert_equal 1, total_queries.size
      assert_match(/GROUP BY "order_items"\."order_id"/, total_queries.first)
      page_query = full_page_queries.find { |sql| sql.match?(/FROM "orders".*ORDER BY/) }
      assert_match(/ORDER BY "orders"\."purchase_at" DESC, "orders"\."order_id" ASC/, page_query)
      assert_match(/LIMIT/, page_query)
      assert_match(/OFFSET/, page_query)
      assert_select "tbody tr", count: 10
      assert_select "td.admin-orders__money", text: "R$ 9,45", count: 1
      assert_select "td.admin-orders__money", text: "R$ 1,25", count: 9
    end

    private

    def query_params(href)
      Rack::Utils.parse_nested_query(URI.parse(href).query)
    end

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
      suffix = next_suffix
      Customer.create!({
        customer_id: "customer-#{suffix}",
        customer_unique_id: "unique-#{suffix}",
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

    def create_item(order:, **attributes)
      suffix = next_suffix
      product = Product.create!(product_id: "product-#{suffix}")
      seller = Seller.create!(
        seller_id: "seller-#{suffix}",
        zip_code_prefix: "01001",
        city: "sao paulo",
        state: "SP"
      )
      OrderItem.create!({
        order: order,
        product: product,
        seller: seller,
        shipping_limit_at: Time.utc(2017, 10, 6)
      }.merge(attributes))
    end

    def create_payment(order:, **attributes)
      OrderPayment.create!({
        order: order,
        payment_type: "credit_card",
        payment_installments: 1
      }.merge(attributes))
    end

    def next_suffix
      @record_sequence += 1
      format("%03d", @record_sequence)
    end
  end
end
