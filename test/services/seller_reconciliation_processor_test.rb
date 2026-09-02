require "test_helper"
require_relative "../support/reconciliation_test_data"

class SellerReconciliationProcessorTest < ActiveSupport::TestCase
  include ReconciliationTestData

  setup { build_reconciliation_data }

  test "reconciles distinct seller orders at inclusive boundaries using complete order totals" do
    reconciliation = processing_reconciliation
    matched = create_reconciliation_order(
      purchase_at: Time.utc(2018, 1, 1),
      items: [
        { price: "10.01", freight: "0.02" },
        { price: "2.00", freight: "0.00" },
        { seller: @other_reconciliation_seller, price: "5.00", freight: "1.00" }
      ],
      payments: [ "10.00", "8.03" ]
    )
    missing = create_reconciliation_order(
      purchase_at: Time.utc(2018, 1, 31, 23, 59, 59),
      items: [ { price: "3.30", freight: "0.03" } ]
    )
    mismatch = create_reconciliation_order(
      purchase_at: Time.utc(2018, 1, 15),
      items: [
        { price: "0.10", freight: "0.20" },
        { seller: @other_reconciliation_seller, price: "0.30", freight: "0.40" }
      ],
      payments: [ "0.49", "0.50" ]
    )
    create_reconciliation_order(
      purchase_at: Time.utc(2017, 12, 31, 23, 59, 59),
      items: [ { price: 50, freight: 0 } ], payments: [ 50 ]
    )
    create_reconciliation_order(
      purchase_at: Time.utc(2018, 2, 1),
      items: [ { price: 50, freight: 0 } ], payments: [ 50 ]
    )
    create_reconciliation_order(
      purchase_at: Time.utc(2018, 1, 15),
      seller: @other_reconciliation_seller,
      items: [ { price: 50, freight: 0 } ], payments: [ 50 ]
    )

    sql = capture_reconciliation_sql do
      assert SellerReconciliationProcessor.new(
        reconciliation_id: reconciliation.id,
        processing_token: reconciliation.processing_token
      ).process
    end

    reconciliation.reload
    assert_equal "completed", reconciliation.status
    assert_nil reconciliation.processing_token
    assert_equal 3, reconciliation.orders_checked
    assert_equal 1, reconciliation.matched_orders
    assert_equal 2, reconciliation.inconsistent_orders
    assert_equal 1, reconciliation.missing_payment_orders
    assert_equal 1, reconciliation.amount_mismatch_orders
    assert_equal BigDecimal("22.36"), reconciliation.expected_value
    assert_equal BigDecimal("19.02"), reconciliation.paid_value
    assert_equal BigDecimal("-3.34"), reconciliation.difference
    assert_equal reconciliation.orders_checked,
      reconciliation.matched_orders + reconciliation.inconsistent_orders
    assert_equal reconciliation.inconsistent_orders,
      reconciliation.missing_payment_orders + reconciliation.amount_mismatch_orders

    assert_equal(
      [
        [ mismatch.order_id, "amount_mismatch", "1.0", "0.99", "-0.01" ],
        [ missing.order_id, "missing_payment", "3.33", "0.0", "-3.33" ]
      ].sort,
      reconciliation.discrepancies.order(:external_order_id).map do |discrepancy|
        [
          discrepancy.external_order_id,
          discrepancy.issue_type,
          discrepancy.expected_value.to_s,
          discrepancy.paid_value.to_s,
          discrepancy.difference.to_s
        ]
      end
    )
    refute_includes reconciliation.discrepancies.pluck(:external_order_id), matched.order_id

    aggregate_queries = sql.grep(/WITH qualified_orders/i)
    assert_equal 1, aggregate_queries.length, "expected one set-based aggregate statement"
    assert_match(/payment_totals/i, aggregate_queries.first)
    assert_match(/INSERT INTO seller_reconciliation_discrepancies/i, aggregate_queries.first)
  end

  test "completes an empty range with exact zero summary and no discrepancies" do
    reconciliation = processing_reconciliation(
      start_date: Date.new(2019, 1, 1), end_date: Date.new(2019, 1, 1)
    )

    SellerReconciliationProcessor.new(
      reconciliation_id: reconciliation.id,
      processing_token: reconciliation.processing_token
    ).process

    reconciliation.reload
    assert_equal "completed", reconciliation.status
    assert_equal [ 0, 0, 0, 0, 0 ], [
      reconciliation.orders_checked,
      reconciliation.matched_orders,
      reconciliation.inconsistent_orders,
      reconciliation.missing_payment_orders,
      reconciliation.amount_mismatch_orders
    ]
    assert_equal [ BigDecimal("0.00"), BigDecimal("0.00"), BigDecimal("0.00") ], [
      reconciliation.expected_value, reconciliation.paid_value, reconciliation.difference
    ]
    assert_empty reconciliation.discrepancies
  end

  test "a stale token cannot delete or overwrite another attempt snapshot" do
    reconciliation = processing_reconciliation
    create_discrepancy(reconciliation, order_id: "stable_external_order")

    result = SellerReconciliationProcessor.new(
      reconciliation_id: reconciliation.id,
      processing_token: SecureRandom.uuid
    ).process

    refute result
    assert_equal "processing", reconciliation.reload.status
    assert_equal [ "stable_external_order" ], reconciliation.discrepancies.pluck(:external_order_id)
  end

  test "a failure after discrepancy insertion rolls back the whole snapshot" do
    reconciliation = processing_reconciliation
    original = create_discrepancy(reconciliation, order_id: "original_external_order")
    create_reconciliation_order(
      purchase_at: Time.utc(2018, 1, 15),
      items: [ { price: 10, freight: 0 } ],
      payments: [ 9 ]
    )
    failing_processor = Class.new(SellerReconciliationProcessor) do
      private

      def verify_snapshot!(_summary)
        raise "snapshot publication failed"
      end
    end

    assert_raises(RuntimeError) do
      failing_processor.new(
        reconciliation_id: reconciliation.id,
        processing_token: reconciliation.processing_token
      ).process
    end

    reconciliation.reload
    assert_equal "processing", reconciliation.status
    assert_nil reconciliation.orders_checked
    assert_equal [ original.id ], reconciliation.discrepancies.pluck(:id)
  end

  private

  def processing_reconciliation(start_date: Date.new(2018, 1, 1), end_date: Date.new(2018, 1, 31))
    create_reconciliation(
      start_date: start_date,
      end_date: end_date,
      status: "processing",
      processing_token: SecureRandom.uuid
    )
  end

  def capture_reconciliation_sql
    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] unless payload[:name] == "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    statements
  end
end
