require "test_helper"

class SellerPerformanceReportCsvTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @seller = create_seller("requested-seller")
    @other_seller = create_seller("other-seller")
    @product = Product.create!(product_id: "report-product", category_name: "books")
    @customer = Customer.create!(
      customer_id: "report-customer",
      customer_unique_id: "report-customer-unique",
      zip_code_prefix: "01001",
      city: "curitiba",
      state: "PR"
    )
  end

  test "generates ordered monthly seller-only exact aggregates in one database query" do
    january_late = create_order(
      "january-late",
      purchase_at: Time.utc(2018, 1, 1),
      delivered_at: Time.utc(2018, 1, 12),
      estimated_at: Time.utc(2018, 1, 11)
    )
    create_item(january_late, @seller, 1, price: "10.01", freight: "0.10")
    create_item(january_late, @seller, 2, price: "20.02", freight: "0.20")
    create_item(january_late, @other_seller, 3, price: "999.99", freight: "88.88")

    january_undelivered = create_order(
      "january-undelivered",
      purchase_at: Time.utc(2018, 1, 31, 23, 59, 59),
      delivered_at: nil,
      estimated_at: Time.utc(2018, 2, 10)
    )
    create_item(january_undelivered, @seller, 1, price: "0.02", freight: "0.03")

    february_on_boundary = create_order(
      "february-on-boundary",
      purchase_at: Time.utc(2018, 2, 1),
      delivered_at: Time.utc(2018, 2, 20),
      estimated_at: Time.utc(2018, 2, 20)
    )
    create_item(february_on_boundary, @seller, 1, price: "0.10", freight: "0.01")

    february_late = create_order(
      "february-late",
      purchase_at: Time.utc(2018, 2, 28, 23, 59, 59),
      delivered_at: Time.utc(2018, 3, 11, 0, 0, 1),
      estimated_at: Time.utc(2018, 3, 11)
    )
    create_item(february_late, @seller, 1, price: "0.20", freight: "0.02")

    outside_before = create_order(
      "outside-before",
      purchase_at: Time.utc(2017, 12, 31, 23, 59, 59),
      delivered_at: nil,
      estimated_at: Time.utc(2018, 1, 10)
    )
    create_item(outside_before, @seller, 1, price: "500.00", freight: "50.00")
    outside_after = create_order(
      "outside-after",
      purchase_at: Time.utc(2018, 3, 1),
      delivered_at: nil,
      estimated_at: Time.utc(2018, 3, 20)
    )
    create_item(outside_after, @seller, 1, price: "600.00", freight: "60.00")

    report = SellerPerformanceReport.create!(
      seller: @seller,
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 2, 28)
    )

    statements = capture_select_sql do
      @csv = SellerPerformanceReportCsv.new(report).generate
    end

    assert_equal(
      [
        SellerPerformanceReportCsv::HEADERS,
        %w[2018-01 2 3 30.05 0.33 15.03 1 50.00],
        %w[2018-02 2 2 0.30 0.03 0.15 1 50.00]
      ],
      CSV.parse(@csv)
    )

    aggregate_queries = statements.grep(/FROM "order_items"/)
    assert_equal 1, aggregate_queries.size, "expected one aggregate query, got #{aggregate_queries.inspect}"
    assert_match(/COUNT\(DISTINCT orders\.id\)/i, aggregate_queries.first)
    assert_match(/GROUP BY DATE_TRUNC\('month', orders\.purchase_at\)/i, aggregate_queries.first)
    assert_match(/"order_items"\."seller_id" = \$1/i, aggregate_queries.first)
  end

  test "returns only the contractual header when no orders qualify" do
    report = SellerPerformanceReport.create!(
      seller: @seller,
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31)
    )

    assert_equal [ SellerPerformanceReportCsv::HEADERS ],
      CSV.parse(SellerPerformanceReportCsv.new(report).generate)
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

  def create_order(external_id, purchase_at:, delivered_at:, estimated_at:)
    Order.create!(
      customer: @customer,
      order_id: external_id,
      status: delivered_at ? "delivered" : "shipped",
      purchase_at: purchase_at,
      approved_at: purchase_at,
      delivered_carrier_at: delivered_at && delivered_at - 2.days,
      delivered_customer_at: delivered_at,
      estimated_delivery_at: estimated_at
    )
  end

  def create_item(order, seller, item_number, price:, freight:)
    OrderItem.create!(
      order: order,
      product: @product,
      seller: seller,
      order_item_id: item_number,
      price: price,
      freight_value: freight,
      shipping_limit_at: order.purchase_at + 2.days
    )
  end

  def capture_select_sql
    statements = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next unless payload[:sql].match?(/\ASELECT\b/i)

      statements << payload[:sql]
    end

    ActiveRecord::Base.connection.clear_query_cache
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    statements
  end
end
