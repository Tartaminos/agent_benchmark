require "test_helper"

class OrderExportCsvTest < ActiveSupport::TestCase
  HEADERS = "order_id,customer_id,customer_state,order_status,delivery_status,purchase_at," \
    "estimated_delivery_at,delivered_customer_at,items_total,freight_total,order_total,paid_total\n"

  setup do
    @sp_customer = create_customer("csv_export_customer_sp_000001", "csv_unique_sp_000000000000001", "SP")
    @rj_customer = create_customer("csv_export_customer_rj_000001", "csv_unique_rj_000000000000001", "RJ")
    @seller = Seller.create!(
      seller_id: "csv_export_seller_000000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @product = Product.create!(product_id: "csv_export_product_00000000001")
  end

  test "generates the exact deterministic contract with combined filters inclusive dates and decimal totals" do
    later_id = create_order(
      "zz_csv_export_matching_00000001",
      customer: @sp_customer,
      status: "delivered",
      purchase_at: Time.utc(2018, 1, 31, 23, 59, 59, 999_999),
      estimated_at: Time.utc(2018, 2, 2),
      delivered_at: Time.utc(2018, 2, 2, 0, 0, 1)
    )
    add_item(later_id, 1, price: "0.10", freight: "0.20")
    add_item(later_id, 2, price: "0.20", freight: "0.10")
    add_payment(later_id, 1, "0.60")

    earlier_id = create_order(
      "aa_csv_export_matching_00000001",
      customer: @sp_customer,
      status: "delivered",
      purchase_at: later_id.purchase_at,
      estimated_at: Time.utc(2018, 2, 1),
      delivered_at: Time.utc(2018, 2, 3)
    )
    add_item(earlier_id, 1, price: "10.01", freight: "1.09")
    add_payment(earlier_id, 1, "5.55")
    add_payment(earlier_id, 2, "5.55")

    excluded = create_order(
      "csv_export_wrong_state_000000001",
      customer: @rj_customer,
      status: "delivered",
      purchase_at: Time.utc(2018, 1, 15),
      estimated_at: Time.utc(2018, 1, 20),
      delivered_at: Time.utc(2018, 1, 21)
    )
    add_item(excluded, 1, price: "999.99", freight: "99.99")
    add_payment(excluded, 1, "1099.98")

    export = OrderExport.create!(
      order_status: "delivered",
      delivery_status: "late",
      customer_state: "SP",
      purchase_from: Date.new(2018, 1, 1),
      purchase_to: Date.new(2018, 1, 31)
    )

    assert_equal(
      HEADERS +
        "aa_csv_export_matching_00000001,csv_export_customer_sp_000001,SP,delivered,late," \
          "2018-01-31T23:59:59.999Z,2018-02-01T00:00:00.000Z,2018-02-03T00:00:00.000Z," \
          "10.01,1.09,11.10,11.10\n" +
        "zz_csv_export_matching_00000001,csv_export_customer_sp_000001,SP,delivered,late," \
          "2018-01-31T23:59:59.999Z,2018-02-02T00:00:00.000Z,2018-02-02T00:00:01.000Z," \
          "0.30,0.30,0.60,0.60\n",
      OrderExportCsv.new(export).generate
    )
  end

  test "supports independent date boundaries and all delivery classifications" do
    pending = create_order(
      "csv_export_pending_000000000001",
      customer: @sp_customer,
      status: "processing",
      purchase_at: Time.utc(2018, 1, 1),
      estimated_at: Time.utc(2018, 1, 10),
      delivered_at: nil
    )
    on_time = create_order(
      "csv_export_ontime_000000000001",
      customer: @sp_customer,
      status: "delivered",
      purchase_at: Time.utc(2018, 1, 15),
      estimated_at: Time.utc(2018, 1, 20),
      delivered_at: Time.utc(2018, 1, 20)
    )
    late = create_order(
      "csv_export_late_00000000000001",
      customer: @sp_customer,
      status: "delivered",
      purchase_at: Time.utc(2018, 1, 31, 23, 59, 59, 999_999),
      estimated_at: Time.utc(2018, 2, 1),
      delivered_at: Time.utc(2018, 2, 2)
    )

    assert_equal [ pending.order_id ], exported_order_ids(OrderExport.create!(delivery_status: "pending", purchase_to: Date.new(2018, 1, 1)))
    assert_equal [ on_time.order_id ], exported_order_ids(OrderExport.create!(delivery_status: "on_time", purchase_from: Date.new(2018, 1, 2)))
    assert_equal [ late.order_id ], exported_order_ids(OrderExport.create!(delivery_status: "late", purchase_to: Date.new(2018, 1, 31)))
  end

  test "returns only the exact header when no orders qualify" do
    export = OrderExport.create!(customer_state: "AC", purchase_to: Date.new(2018, 1, 1))

    assert_equal HEADERS, OrderExportCsv.new(export).generate
  end

  test "uses bounded set queries for customers item totals and payment totals rather than per-order queries" do
    12.times do |index|
      order = create_order(
        format("csv_export_query_%014d", index),
        customer: @sp_customer,
        status: "delivered",
        purchase_at: Time.utc(2018, 1, 1) + index.hours,
        estimated_at: Time.utc(2018, 1, 10),
        delivered_at: nil
      )
      add_item(order, 1, price: "1.00", freight: "0.10")
      add_payment(order, 1, "1.10")
    end
    export = OrderExport.create!(customer_state: "SP", purchase_to: Date.new(2018, 1, 31))

    select_count = count_selects { OrderExportCsv.new(export).generate }

    assert_equal 4, select_count
  end

  private

  def create_customer(customer_id, unique_id, state)
    Customer.create!(
      customer_id: customer_id,
      customer_unique_id: unique_id,
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: state
    )
  end

  def create_order(order_id, customer:, status:, purchase_at:, estimated_at:, delivered_at:)
    Order.create!(
      order_id: order_id,
      customer: customer,
      status: status,
      purchase_at: purchase_at,
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

  def exported_order_ids(export)
    CSV.parse(OrderExportCsv.new(export).generate, headers: true).map { |row| row.fetch("order_id") }
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
