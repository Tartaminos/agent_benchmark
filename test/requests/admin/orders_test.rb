require "test_helper"

class Admin::OrdersTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @sp_customer = create_customer("sp", state: "SP", city: "sao paulo")
    @rj_customer = create_customer("rj", state: "RJ", city: "rio de janeiro")

    @old_order = create_order(
      "external_order_old", customer: @rj_customer, status: "canceled",
      purchase_at: Time.utc(2018, 1, 1, 9), estimated_at: Time.utc(2018, 1, 8)
    )
    @matching_order = create_order(
      "external_order_match", customer: @sp_customer, status: "delivered",
      purchase_at: Time.utc(2018, 1, 2, 23, 59, 59),
      estimated_at: Time.utc(2018, 1, 10, 12), delivered_at: Time.utc(2018, 1, 9, 12)
    )
    @late_order = create_order(
      "external_order_late", customer: @sp_customer, status: "delivered",
      purchase_at: Time.utc(2018, 1, 3, 10),
      estimated_at: Time.utc(2018, 1, 10, 12), delivered_at: Time.utc(2018, 1, 10, 12, 0, 1)
    )
    @boundary_order = create_order(
      "external_order_boundary", customer: @rj_customer, status: "delivered",
      purchase_at: Time.utc(2018, 1, 4, 10),
      estimated_at: Time.utc(2018, 1, 10, 12, 0, 0, 123_000),
      delivered_at: Time.utc(2018, 1, 10, 12, 0, 0, 123_000)
    )
    @pending_order = create_order(
      "external_order_pending", customer: @sp_customer, status: "shipped",
      purchase_at: Time.utc(2018, 1, 5, 10),
      estimated_at: Time.utc(2018, 1, 4, 10), delivered_at: nil
    )

    @product = Product.create!(product_id: "admin_product")
    @seller = Seller.create!(
      seller_id: "admin_seller", zip_code_prefix: "01001", city: "sao paulo", state: "SP"
    )
    create_item(@matching_order, 1, price: "10.10", freight: "0.05")
    create_item(@matching_order, 2, price: "2.00", freight: "3.40")
    OrderPayment.create!(
      order: @matching_order, payment_sequential: 1, payment_type: "credit_card",
      payment_installments: 2, payment_value: "12.00"
    )
    OrderPayment.create!(
      order: @matching_order, payment_sequential: 2, payment_type: "voucher",
      payment_installments: 1, payment_value: "3.55"
    )
  end

  test "index renders accessible order semantics with newest-first data, derived statuses, totals, and external IDs" do
    sql = capture_request_sql { get "/admin/orders" }

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_equal 3, sql.size, "expected count, bounded page, and one page-wide totals query: #{sql.inspect}"
    assert sql.all? { |statement| statement.match?(/\ASELECT\b/i) },
           "expected a read-only listing, got: #{sql.join("\n\n")}"
    assert_match(/\bLIMIT\b/i, sql.second)

    assert_select "h1", text: "Orders"
    assert_select "form label[for=order_id]", text: "Search by order ID"
    assert_select "form label[for=status]", text: "Order status"
    assert_select "form label[for=delivery_status]", text: "Delivery status"
    assert_select "form label[for=customer_state]", text: "Customer state"
    assert_select "table caption", text: "Filtered Olist orders"
    assert_select "nav[aria-label='Orders pagination']"
    assert_select ".admin-nav-list .admin-nav-link", count: 1, text: /Orders/
    assert_select ".admin-nav-list span.admin-nav-link", count: 0
    assert_select ".admin-user", count: 0
    refute_match(/Admin User|admin@example\.com|Dashboard|Customers|Products|Sellers|Reviews|Payments|Reports|Settings/,
                 response.body)
    assert_select ".admin-shell > turbo-frame#order_details.order-detail-frame[data-controller=order-details]" do |frames|
      assert_equal "turbo:before-fetch-request->order-details#loading turbo:frame-load->order-details#loaded",
                   frames.sole["data-action"]
      assert_select ".frame-status[role=status][aria-live=polite][aria-atomic=true]" \
                    "[data-order-details-target=status]",
                    text: "Loading order details…"
    end
    assert_equal(
      %w[external_order_pending external_order_boundary external_order_late external_order_match external_order_old],
      table_order_ids
    )
    assert_select "tr", text: /external_order_pending.*Pending/m
    assert_select "tr", text: /external_order_boundary.*On time/m
    assert_select "tr", text: /external_order_late.*Late/m
    assert_select "tr", text: /external_order_match.*R\$ 15,55/m
    assert_select "a[href^='/admin/orders/#{@matching_order.order_id}?'][data-turbo-frame='order_details']"
    assert_select "a[href='/admin/orders/#{@matching_order.id}']", count: 0
  end

  test "index combines exact external ID, status, delivery, state, and inclusive purchase-date filters" do
    filters = {
      order_id: @matching_order.order_id,
      status: "delivered",
      delivery_status: "on_time",
      customer_state: "sp",
      purchase_from: "2018-01-02",
      purchase_to: "2018-01-02"
    }

    get "/admin/orders", params: filters

    assert_response :success
    assert_equal [ @matching_order.order_id ], table_order_ids

    get "/admin/orders", params: filters.merge(order_id: "external_order")

    assert_response :success
    assert_select ".empty-state h3", text: "No orders match these filters"
    assert_equal [], table_order_ids
  end

  test "delivery filters honor pending precedence, equality as on-time, and strictly later as late" do
    {
      "pending" => [ @pending_order.order_id, @old_order.order_id ],
      "on_time" => [ @boundary_order.order_id, @matching_order.order_id ],
      "late" => [ @late_order.order_id ]
    }.each do |delivery_status, expected_ids|
      get "/admin/orders", params: { delivery_status: delivery_status }

      assert_response :success
      assert_equal expected_ids, table_order_ids, "wrong result for #{delivery_status}"
    end
  end

  test "purchase sorting defaults descending and supports ascending with deterministic ties" do
    tied_a = create_order(
      "external_tie_a", customer: @sp_customer, status: "processing",
      purchase_at: Time.utc(2018, 1, 6, 10), estimated_at: Time.utc(2018, 1, 12)
    )
    tied_b = create_order(
      "external_tie_b", customer: @sp_customer, status: "processing",
      purchase_at: tied_a.purchase_at, estimated_at: Time.utc(2018, 1, 12)
    )

    get "/admin/orders"
    assert_equal %w[external_tie_a external_tie_b], table_order_ids.first(2)

    get "/admin/orders", params: { sort: "asc" }
    assert_response :success
    assert_equal @old_order.order_id, table_order_ids.first
    assert_equal %w[external_tie_a external_tie_b], table_order_ids.last(2)
    assert_select "select[name=sort] option[value=asc][selected=selected]", text: "Oldest first"
  end

  test "pagination stays database-bounded and retains filters and sorting in all navigation paths" do
    11.times do |number|
      create_order(
        format("external_bulk_%02d", number), customer: @sp_customer, status: "delivered",
        purchase_at: Time.utc(2018, 2, 1) + number.hours,
        estimated_at: Time.utc(2018, 2, 10), delivered_at: Time.utc(2018, 2, 9)
      )
    end
    params = {
      status: "delivered", delivery_status: "on_time", customer_state: "SP",
      purchase_from: "2018-01-01", purchase_to: "2018-12-31", sort: "asc"
    }

    sql = capture_request_sql { get "/admin/orders", params: params }

    assert_response :success
    assert_equal 10, table_order_ids.size
    assert_equal 3, sql.size, "expected query count independent of rows rendered: #{sql.inspect}"
    page_sql = sql.find { |statement| statement.match?(/\bLIMIT\b/i) }
    assert page_sql, "expected SQL-level pagination: #{sql.inspect}"
    assert_match(/LIMIT/i, page_sql)

    next_link = css_select("a[rel=next]").sole
    next_query = Rack::Utils.parse_nested_query(URI.parse(next_link["href"]).query)
    assert_equal params.stringify_keys.merge("page" => "2"), next_query
    assert_equal "Next", next_link.text.strip
    assert_select "form.sort-form" do
      params.except(:sort).each { |key, value| assert_select "input[name=#{key}][value='#{value}']" }
    end
    detail_link = css_select("a.order-id").first["href"]
    detail_query = Rack::Utils.parse_nested_query(URI.parse(detail_link).query)
    assert_equal params.stringify_keys.merge("page" => "1"), detail_query.except("list_order_id")
    assert_nil detail_query["order_id"]
    assert_select "a.button-secondary[href='/admin/orders']", text: "Clear filters"

    get "/admin/orders", params: params.merge(page: 2)
    assert_response :success
    assert_equal 2, table_order_ids.size
    assert_select "a[rel=prev]"
  end

  test "direct and Turbo details render summary, customer, derived status, and independent totals" do
    sql = capture_request_sql do
      get "/admin/orders/#{@matching_order.order_id}", params: originating_detail_params.merge(ignored: "drop-me")
    end

    assert_response :success
    assert_equal 4, sql.size, "expected order/customer plus two aggregate queries: #{sql.inspect}"
    assert sql.all? { |statement| statement.match?(/\ASELECT\b/i) },
           "expected read-only details, got: #{sql.join("\n\n")}"
    assert_select ".detail-page-shell"
    assert_select "h1#detail-heading", text: "Order #{@matching_order.order_id}"
    assert_select "#summary-heading", text: "Order summary"
    assert_select ".detail-card", text: /Order ID.*external_order_match/m
    assert_select ".detail-card", text: /Delivery status.*On time/m
    assert_select "#customer-heading", text: "Customer"
    assert_select ".detail-card", text: /customer_external_sp.*unique_external_sp.*SP.*sao paulo/m
    assert_select "#totals-heading", text: "Totals"
    assert_select ".detail-card", text: /Items total.*R\$ 12,10/m
    assert_select ".detail-card", text: /Freight total.*R\$ 3,45/m
    assert_select ".detail-card", text: /Order total.*R\$ 15,55/m
    assert_select ".detail-card", text: /Paid total.*R\$ 15,55/m
    refute_includes response.body, "/admin/orders/#{@matching_order.id}"
    assert_equal expected_listing_query, link_query("a.detail-close")

    get "/admin/orders/#{@matching_order.order_id}",
        params: originating_detail_params.merge(ignored: "drop-me"),
        headers: { "Turbo-Frame" => "order_details" }

    assert_response :success
    assert_select "turbo-frame#order_details[data-controller=order-details]" do |frames|
      assert_equal "turbo:before-fetch-request->order-details#loading turbo:frame-load->order-details#loaded",
                   frames.sole["data-action"]
      assert_select ".frame-status[role=status][aria-live=polite][aria-atomic=true]" \
                    "[data-order-details-target=status]",
                    text: "Order details loaded."
    end
    assert_select ".detail-page-shell", count: 0
    assert_select "h1", count: 0
    assert_select "h2#detail-heading[tabindex='-1'][data-order-details-target=heading]",
                  text: "Order #{@matching_order.order_id}"
    assert_equal expected_listing_query, link_query("a.detail-close")
    assert_select "a[data-turbo-frame='_top']", text: "View full details"
    assert_equal originating_detail_params.stringify_keys, link_query("a.detail-full")
  end

  test "unknown external and internal IDs render the unavailable state with 404" do
    [ "does-not-exist", @matching_order.id.to_s ].each do |order_id|
      get "/admin/orders/#{order_id}", params: originating_detail_params.merge(ignored: "drop-me")

      assert_response :not_found
      assert_select "h1", text: "Order unavailable"
      assert_select "[role=alert] h2", text: "We couldn't find this order"
      assert_select ".unavailable-state a[href^='/admin/orders?']", text: "Back to orders"
      assert_equal expected_listing_query, link_query(".unavailable-state a")
    end
  end

  test "invalid dates and reversed ranges return 422 while valid no-match filters show an explicit empty state" do
    {
      "not-a-date" => "Start date must be a valid date.",
      "2018-02-30" => "Start date must be a valid date."
    }.each do |value, message|
      get "/admin/orders", params: { purchase_from: value }

      assert_response :unprocessable_content
      assert_select "[role=alert]", text: /#{Regexp.escape(message)}/
      assert_select "tbody tr", count: 0
    end

    get "/admin/orders", params: { purchase_from: "2018-02-02", purchase_to: "2018-02-01" }
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Start date must be on or before end date/

    get "/admin/orders", params: { order_id: "missing-external-order" }
    assert_response :success
    assert_select ".empty-state h3", text: "No orders match these filters"
    assert_select "a[href='/admin/orders']", text: "Clear filters"
  end

  private

  def create_customer(suffix, state:, city:)
    Customer.create!(
      customer_id: "customer_external_#{suffix}",
      customer_unique_id: "unique_external_#{suffix}",
      zip_code_prefix: "01001", city: city, state: state
    )
  end

  def create_order(external_id, customer:, status:, purchase_at:, estimated_at:, delivered_at: nil)
    Order.create!(
      order_id: external_id, customer: customer, status: status, purchase_at: purchase_at,
      estimated_delivery_at: estimated_at, delivered_customer_at: delivered_at
    )
  end

  def create_item(order, sequence, price:, freight:)
    OrderItem.create!(
      order: order, product: @product, seller: @seller, order_item_id: sequence,
      shipping_limit_at: order.purchase_at + 1.day, price: price, freight_value: freight
    )
  end

  def table_order_ids
    css_select("table tbody a.order-id span").map { |node| node.text.strip }
  end

  def originating_detail_params
    {
      list_order_id: @matching_order.order_id,
      status: "delivered",
      delivery_status: "on_time",
      customer_state: "SP",
      purchase_from: "2018-01-01",
      purchase_to: "2018-01-31",
      sort: "asc",
      page: "2"
    }
  end

  def expected_listing_query
    originating_detail_params.stringify_keys.except("list_order_id").merge(
      "order_id" => @matching_order.order_id
    )
  end

  def link_query(selector)
    href = css_select(selector).sole["href"]
    Rack::Utils.parse_nested_query(URI.parse(href).query)
  end

  def capture_request_sql
    counter = ActiveRecord::Assertions::QueryAssertions::SQLCounter.new
    ActiveRecord::Base.lease_connection.materialize_transactions
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    end
    counter.log
  end
end
