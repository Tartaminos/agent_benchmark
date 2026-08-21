require "test_helper"

class SellerPerformanceReportCsvTest < ActiveSupport::TestCase
  HEADERS = "month,orders,items,gross_value,freight,average_order_value,late_orders,late_percentage\n"

  setup do
    @customer = Customer.create!(
      customer_id: "csv_customer_external_000000001",
      customer_unique_id: "csv_customer_unique_0000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @seller = create_seller("csv_report_seller_0000000000001")
    @other_seller = create_seller("csv_other_seller_00000000000001")
    @product = Product.create!(product_id: "csv_product_external_0000000001")
    @report = @seller.seller_performance_reports.create!(
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 2, 28)
    )
  end

  test "generates the exact ordered monthly contract with seller isolation and inclusive UTC dates" do
    january_late = create_order(
      "csv_january_late_000000000001",
      purchase_at: Time.utc(2018, 1, 1),
      estimated_at: Time.utc(2018, 1, 10),
      delivered_at: Time.utc(2018, 1, 10, 0, 0, 1)
    )
    add_item(january_late, @seller, 1, price: "10.01", freight: "0.10")
    add_item(january_late, @seller, 2, price: "0.02", freight: "0.20")
    add_item(january_late, @other_seller, 3, price: "999.99", freight: "99.99")

    january_on_time = create_order(
      "csv_january_ontime_0000000001",
      purchase_at: Time.utc(2018, 1, 15, 12),
      estimated_at: Time.utc(2018, 1, 20),
      delivered_at: Time.utc(2018, 1, 20)
    )
    add_item(january_on_time, @seller, 1, price: "0.10", freight: "0.02")

    january_undelivered = create_order(
      "csv_january_pending_000000000",
      purchase_at: Time.utc(2018, 1, 31, 23, 59, 59, 999_999),
      estimated_at: Time.utc(2018, 2, 5),
      delivered_at: nil
    )
    add_item(january_undelivered, @seller, 1, price: "0.01", freight: "0.01")

    february = create_order(
      "csv_february_boundary_00000001",
      purchase_at: Time.utc(2018, 2, 28, 23, 59, 59, 999_999),
      estimated_at: Time.utc(2018, 3, 2),
      delivered_at: Time.utc(2018, 3, 3)
    )
    add_item(february, @seller, 1, price: "20.00", freight: "1.50")

    before_range = create_order(
      "csv_before_range_0000000000001",
      purchase_at: Time.utc(2017, 12, 31, 23, 59, 59),
      estimated_at: Time.utc(2018, 1, 2),
      delivered_at: nil
    )
    add_item(before_range, @seller, 1, price: "50.00", freight: "5.00")
    after_range = create_order(
      "csv_after_range_00000000000001",
      purchase_at: Time.utc(2018, 3, 1),
      estimated_at: Time.utc(2018, 3, 4),
      delivered_at: nil
    )
    add_item(after_range, @seller, 1, price: "60.00", freight: "6.00")

    assert_equal(
      HEADERS +
        "2018-01,3,4,10.14,0.33,3.38,1,33.33\n" +
        "2018-02,1,1,20.00,1.50,20.00,1,100.00\n",
      SellerPerformanceReportCsv.new(@report).generate
    )
  end

  test "returns only the header when no qualifying orders exist" do
    assert_equal HEADERS, SellerPerformanceReportCsv.new(@report).generate
  end

  test "performs one bounded aggregation query rather than queries per order" do
    30.times do |index|
      order = create_order(
        format("csv_query_order_%015d", index),
        purchase_at: Time.utc(2018, 1, 1) + index.hours,
        estimated_at: Time.utc(2018, 1, 10),
        delivered_at: nil
      )
      add_item(order, @seller, 1, price: "1.00", freight: "0.10")
    end

    select_count = count_selects { SellerPerformanceReportCsv.new(@report).generate }

    assert_equal 1, select_count
  end

  private

  def create_seller(seller_id)
    Seller.create!(
      seller_id: seller_id,
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  def create_order(order_id, purchase_at:, estimated_at:, delivered_at:)
    Order.create!(
      order_id: order_id,
      customer: @customer,
      status: "delivered",
      purchase_at: purchase_at,
      estimated_delivery_at: estimated_at,
      delivered_customer_at: delivered_at
    )
  end

  def add_item(order, seller, item_number, price:, freight:)
    order.order_items.create!(
      order_item_id: item_number,
      product: @product,
      seller: seller,
      shipping_limit_at: order.purchase_at + 1.day,
      price: BigDecimal(price),
      freight_value: BigDecimal(freight)
    )
  end

  def count_selects
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
