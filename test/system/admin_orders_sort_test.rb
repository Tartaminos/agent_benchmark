require "application_system_test_case"

class AdminOrdersSortTest < ApplicationSystemTestCase
  self.fixture_table_names = []

  setup do
    customer = Customer.create!(
      customer_id: "system_sort_customer",
      customer_unique_id: "system_sort_unique",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    create_order("external_sort_old", customer, Time.utc(2018, 1, 1))
    create_order("external_sort_new", customer, Time.utc(2018, 1, 2))
  end

  test "changing the accessibly labelled sort submits and retains active filters" do
    visit admin_orders_path(status: "delivered", customer_state: "SP")

    assert_selector "#filter_sort", count: 1, visible: :hidden
    assert_selector "select#orders_sort", count: 1
    assert_equal %w[external_sort_new external_sort_old], rendered_order_ids

    select "Oldest first", from: "Sort by purchase date"

    assert_current_path(/sort=asc/)
    assert_equal(
      { "status" => "delivered", "customer_state" => "SP", "sort" => "asc" },
      Rack::Utils.parse_nested_query(URI.parse(page.current_url).query)
    )
    assert_equal %w[external_sort_old external_sort_new], rendered_order_ids
  end

  private

  def create_order(external_id, customer, purchase_at)
    Order.create!(
      order_id: external_id,
      customer: customer,
      status: "delivered",
      purchase_at: purchase_at,
      delivered_customer_at: purchase_at + 3.days,
      estimated_delivery_at: purchase_at + 4.days
    )
  end

  def rendered_order_ids
    all("table tbody a.order-id span").map(&:text)
  end
end
