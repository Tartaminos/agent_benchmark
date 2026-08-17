require "test_helper"

class GenerateSellerPerformanceReportJobTest < ActiveJob::TestCase
  self.fixture_table_names = []

  setup do
    @customer = Customer.create!(
      customer_id: "performance_customer",
      customer_unique_id: "performance_unique",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @seller = create_seller("performance_seller")
    @other_seller = create_seller("performance_other_seller")
    @product = Product.create!(product_id: "performance_product", category_name: "office")
  end

  test "generation creates exact ordered seller-only monthly aggregates at inclusive date boundaries" do
    january_first = create_order("january_first", Time.utc(2018, 1, 1), late: true)
    create_item(january_first, @seller, 1, "0.10", "0.01")
    create_item(january_first, @seller, 2, "0.20", "0.02")
    create_item(january_first, @other_seller, 3, "999.99", "99.99")

    january_last = create_order("january_last", Time.utc(2018, 1, 31, 23, 59, 59), late: false)
    create_item(january_last, @seller, 1, "10.00", "1.00")
    create_item(january_last, @other_seller, 2, "500.00", "50.00")

    january_third = create_order("january_third", Time.utc(2018, 1, 15), late: nil)
    create_item(january_third, @seller, 1, "0.00", "0.00")

    february_last = create_order("february_last", Time.utc(2018, 2, 28, 23, 59, 59), late: nil)
    create_item(february_last, @seller, 1, "0.10", "0.01")
    create_item(february_last, @seller, 2, "0.20", "0.02")

    before_range = create_order("before_range", Time.utc(2017, 12, 31, 23, 59, 59), late: true)
    create_item(before_range, @seller, 1, "100.00", "10.00")
    after_range = create_order("after_range", Time.utc(2018, 3, 1), late: true)
    create_item(after_range, @seller, 1, "200.00", "20.00")

    report = create_report(start_date: Date.new(2018, 1, 1), end_date: Date.new(2018, 2, 28))
    sql = capture_sql { GenerateSellerPerformanceReportJob.perform_now(report.id) }

    assert_equal "completed", report.reload.status
    assert_equal <<~CSV, report.csv_content
      month,orders,items,gross_value,freight,average_order_value,late_orders,late_percentage
      2018-01,3,4,10.30,1.03,3.43,1,33.33
      2018-02,1,2,0.30,0.03,0.30,0,0.00
    CSV

    aggregate_queries = sql.grep(/FROM "order_items"/i)
    assert_equal 1, aggregate_queries.size, "expected one bounded aggregate query, got: #{sql.inspect}"
    assert_match(/GROUP BY/i, aggregate_queries.first)
    assert_operator sql.grep(/\ASELECT\b/i).size, :<=, 3,
                    "expected bounded SELECT count, got: #{sql.inspect}"
  end

  test "generation is idempotent after completion" do
    order = create_order("idempotent_order", Time.utc(2018, 1, 10), late: false)
    create_item(order, @seller, 1, "12.34", "0.50")
    report = create_report

    GenerateSellerPerformanceReportJob.perform_now(report.id)
    original_csv = report.reload.csv_content
    original_updated_at = report.updated_at

    GenerateSellerPerformanceReportJob.perform_now(report.id)

    assert_equal "completed", report.reload.status
    assert_equal original_csv, report.csv_content
    assert_equal original_updated_at, report.updated_at
  end

  test "generation failure is contained and atomically leaves an identifiable failed report without CSV" do
    report = create_report
    observed_status = nil
    broken_query = Object.new
    broken_query.define_singleton_method(:rows) do
      observed_status = report.reload.status
      raise "private database detail"
    end

    SellerPerformanceReportQuery.singleton_class.define_method(:new) { |**| broken_query }
    begin
      assert_nothing_raised do
        GenerateSellerPerformanceReportJob.perform_now(report.id)
      end
    ensure
      SellerPerformanceReportQuery.singleton_class.remove_method(:new)
    end

    assert_equal "processing", observed_status
    assert_equal "failed", report.reload.status
    assert_nil report.csv_content
    refute_includes report.attributes.values.compact.map(&:to_s), "private database detail"
  end

  private

  def create_seller(external_id)
    Seller.create!(
      seller_id: external_id,
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  def create_order(external_id, purchase_at, late:)
    estimated_at = purchase_at + 7.days
    delivered_at = estimated_at + 1.second if late
    delivered_at = estimated_at if late == false
    Order.create!(
      order_id: external_id,
      customer: @customer,
      status: "delivered",
      purchase_at: purchase_at,
      delivered_customer_at: delivered_at,
      estimated_delivery_at: estimated_at
    )
  end

  def create_item(order, seller, item_number, price, freight)
    OrderItem.create!(
      order: order,
      seller: seller,
      product: @product,
      order_item_id: item_number,
      shipping_limit_at: order.purchase_at + 1.day,
      price: price,
      freight_value: freight
    )
  end

  def create_report(start_date: Date.new(2018, 1, 1), end_date: Date.new(2018, 1, 31))
    SellerPerformanceReport.create!(seller: @seller, start_date: start_date, end_date: end_date)
  end

  def capture_sql
    counter = ActiveRecord::Assertions::QueryAssertions::SQLCounter.new
    ActiveRecord::Base.lease_connection.materialize_transactions
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    end
    counter.log
  end
end
