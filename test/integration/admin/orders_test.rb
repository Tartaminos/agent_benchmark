require "test_helper"

class Admin::OrdersTest < ActionDispatch::IntegrationTest
  setup do
    @customer = create_customer("main", state: "SP")
    @product = Product.create!(product_id: "admin_product_main")
    @seller = Seller.create!(
      seller_id: "admin_seller_main",
      zip_code_prefix: "20001",
      city: "rio de janeiro",
      state: "RJ"
    )
  end

  test "combines filters, includes the full through date, and renders derived state and totals" do
    estimated_at = Time.utc(2024, 3, 31, 20)
    matching = create_order(
      "admin_matching_order",
      customer: @customer,
      purchase_at: Time.utc(2024, 3, 31, 23, 59, 59),
      estimated_at:,
      delivered_at: estimated_at
    )
    add_item(matching, 1, price: "10.25", freight: "1.75")
    add_item(matching, 2, price: "2.00", freight: "0.50")

    create_order(
      "admin_next_day_order",
      customer: @customer,
      purchase_at: Time.utc(2024, 4, 1),
      estimated_at:,
      delivered_at: estimated_at
    )
    create_order(
      "admin_wrong_delivery",
      customer: @customer,
      purchase_at: Time.utc(2024, 3, 31, 12),
      estimated_at:,
      delivered_at: estimated_at + 1.second
    )
    other_customer = create_customer("other", state: "RJ")
    create_order(
      "admin_wrong_state_order",
      customer: other_customer,
      purchase_at: Time.utc(2024, 3, 31, 12),
      estimated_at:,
      delivered_at: estimated_at
    )

    get admin_orders_path, params: {
      order_id: matching.order_id,
      status: "delivered",
      delivery_status: "on_time",
      customer_state: "SP",
      purchased_from: "2024-03-31",
      purchased_through: "2024-03-31"
    }

    assert_response :ok
    assert_select "tbody tr", count: 1 do
      assert_select "th[scope=row]", text: matching.order_id
      assert_select "td", text: "SP"
      assert_select ".status-badge", text: "On time"
      assert_select ".money", text: "R$ 14,50"
      assert_select "a[aria-label=?][data-turbo-frame=order_details][data-order-id=?]",
        "View details for order #{matching.order_id}", matching.order_id
    end
    assert_select "label[for=order_id]", text: "Order ID"
    assert_select "label[for=delivery_status]", text: "Delivery status"
    assert_select "th[scope=col]", text: "Total"
    refute_includes response.body, "admin_next_day_order"
    refute_includes response.body, "admin_wrong_delivery"
    refute_includes response.body, "admin_wrong_state_order"
    assert_select "turbo-frame#order_details[data-controller=order-details] .visually-hidden[role=status]",
      text: "Order details are closed."
  end

  test "sorts deterministically and preserves filters and sorting in pagination links" do
    purchase_at = Time.utc(2024, 5, 1, 12)
    27.times do |index|
      create_order(
        format("admin_page_%02d", index),
        customer: @customer,
        purchase_at: purchase_at + index.days,
        estimated_at: purchase_at + 40.days,
        delivered_at: nil
      )
    end

    get admin_orders_path, params: {
      status: "delivered",
      delivery_status: "pending",
      customer_state: "SP",
      purchased_from: "2024-05-01",
      sort: "asc",
      page: "1"
    }

    assert_response :ok
    rendered_ids = css_select("tbody th[scope=row]").map { |node| node.text.strip }
    assert_equal (0...25).map { |index| format("admin_page_%02d", index) }, rendered_ids
    assert_select "nav[aria-label='Orders pagination'] a[rel=next]" do |links|
      assert_equal 1, links.size
      query = Rack::Utils.parse_nested_query(URI.parse(links.first["href"]).query)
      assert_equal(
        {
          "customer_state" => "SP",
          "delivery_status" => "pending",
          "page" => "2",
          "purchased_from" => "2024-05-01",
          "sort" => "asc",
          "status" => "delivered"
        },
        query
      )
    end
    assert_select ".sort-link--active", text: "Oldest"

    get admin_orders_path, params: { sort: "desc" }
    assert_response :ok
    assert_equal "admin_page_26", css_select("tbody th[scope=row]").first.text.strip
  end

  test "rejects malformed and invalid filter values without querying results" do
    [
      "order_id[]=value",
      "status[value]=delivered",
      "delivery_status[]=late",
      "customer_state[]=SP",
      "purchased_from[value]=2024-01-01",
      "purchased_through[]=2024-01-31",
      "sort[]=asc",
      "page[]=1"
    ].each do |query|
      get "#{admin_orders_path}?#{query}"

      assert_response :unprocessable_content, "expected 422 for #{query}"
      assert_select "[role=alert]", /must be a single value|Page must be a positive whole number/
      assert_select "tbody tr", count: 0
    end

    get admin_orders_path, params: {
      status: "not-a-status",
      delivery_status: "tomorrow",
      customer_state: "XX",
      purchased_from: "2024-02-30",
      purchased_through: "2024-01-01",
      page: "0",
      sort: "sideways"
    }

    assert_response :unprocessable_content
    assert_select "[role=alert] li", minimum: 6
    assert_select "tbody tr", count: 0
  end

  test "renders external identifiers and exact item freight order and payment totals in details" do
    order = create_order(
      "admin_details_order",
      customer: @customer,
      purchase_at: Time.utc(2024, 6, 1),
      estimated_at: Time.utc(2024, 6, 10),
      delivered_at: Time.utc(2024, 6, 11)
    )
    add_item(order, 1, price: "10.10", freight: "0.90")
    add_item(order, 2, price: "2.20", freight: "0.30")
    add_payment(order, 1, "10.00")
    add_payment(order, 2, "3.50")

    get admin_order_path(order.order_id), params: { status: "delivered", sort: "asc", page: "2" }

    assert_response :ok
    assert_select "turbo-frame#order_details[data-controller=order-details]"
    assert_select "h1", text: order.order_id
    assert_select "h2", text: "Order summary"
    assert_select "h2", text: "Customer"
    assert_select "h2", text: "Totals"
    assert_detail_value "Customer ID", @customer.customer_id
    assert_detail_value "Customer unique ID", @customer.customer_unique_id
    assert_detail_value "Item total", "R$ 12,30"
    assert_detail_value "Freight total", "R$ 1,20"
    assert_detail_value "Order total", "R$ 13,50"
    assert_detail_value "Paid total", "R$ 13,50"
    assert_select "a[aria-label='Close order details'][data-order-details-close]" do |links|
      assert_equal 1, links.size
      query = Rack::Utils.parse_nested_query(URI.parse(links.first["href"]).query)
      assert_equal({ "page" => "2", "sort" => "asc", "status" => "delivered" }, query)
    end
    refute_match(%r{/admin/orders/#{order.id}(?:\?|\z)}, response.body)

    get admin_order_path(order.id)

    assert_response :not_found
    assert_select "turbo-frame#order_details[data-controller=order-details] [role=alert]"
    assert_select "h1", text: "Order not found"
    assert_select "[data-order-details-close]", count: 2
  end

  test "distinguishes an empty dataset from filters with no matches" do
    get admin_orders_path

    assert_response :ok
    assert_select ".empty-state h3", text: "No orders are available"

    create_order(
      "admin_existing_order",
      customer: @customer,
      purchase_at: Time.utc(2024, 7, 1),
      estimated_at: Time.utc(2024, 7, 10),
      delivered_at: nil
    )
    get admin_orders_path, params: { order_id: "unknown_external_order" }

    assert_response :ok
    assert_select ".empty-state h3", text: "No orders match these filters"
    assert_select ".empty-state a", text: "Clear filters"
  end

  test "keeps list SELECT count bounded as the page fills" do
    create_order(
      "admin_query_seed",
      customer: @customer,
      purchase_at: Time.utc(2024, 8, 1),
      estimated_at: Time.utc(2024, 8, 10),
      delivered_at: nil
    )
    small_count = select_count { get admin_orders_path }

    29.times do |index|
      order = create_order(
        format("admin_query_%02d", index),
        customer: @customer,
        purchase_at: Time.utc(2024, 8, 2) + index.days,
        estimated_at: Time.utc(2024, 9, 15),
        delivered_at: nil
      )
      add_item(order, 1, price: "1.00", freight: "0.10")
    end
    full_count = select_count { get admin_orders_path }

    assert_response :ok
    assert_equal 25, css_select("tbody tr").size
    assert_operator (small_count - full_count).abs, :<=, 1,
      "expected effectively constant SELECT count, got #{small_count} and #{full_count}"
    assert_operator [ small_count, full_count ].max, :<=, 5,
      "expected a bounded query plan, got #{small_count} and #{full_count} SELECTs"
  end

  private

  def create_customer(suffix, state:)
    Customer.create!(
      customer_id: "admin_customer_#{suffix}",
      customer_unique_id: "admin_unique_#{suffix}",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state:
    )
  end

  def create_order(order_id, customer:, purchase_at:, estimated_at:, delivered_at:)
    Order.create!(
      order_id:,
      customer:,
      status: "delivered",
      purchase_at:,
      estimated_delivery_at: estimated_at,
      delivered_customer_at: delivered_at
    )
  end

  def add_item(order, item_number, price:, freight:)
    order.order_items.create!(
      order_item_id: item_number,
      product: @product,
      seller: @seller,
      shipping_limit_at: order.purchase_at + 1.day,
      price: BigDecimal(price),
      freight_value: BigDecimal(freight)
    )
  end

  def add_payment(order, sequence, value)
    order.order_payments.create!(
      payment_sequential: sequence,
      payment_type: "credit_card",
      payment_installments: 1,
      payment_value: BigDecimal(value)
    )
  end

  def assert_detail_value(label, value)
    assert_select "dt", text: label do |terms|
      assert_equal 1, terms.size
      assert_equal value, terms.first.parent.at_css("dd").text.strip
    end
  end

  def select_count
    count = 0
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload.fetch(:sql)
      count += 1 if sql.match?(/\ASELECT\b/i) && payload[:name] != "SCHEMA" && !payload[:cached]
    end

    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    end
    count
  end
end
