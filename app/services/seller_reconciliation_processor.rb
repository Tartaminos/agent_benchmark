class SellerReconciliationProcessor
  class InconsistentSnapshotError < StandardError; end

  def initialize(reconciliation_id:, processing_token:)
    @reconciliation_id = reconciliation_id
    @processing_token = processing_token
  end

  def process
    SellerReconciliation.transaction do
      reconciliation = locked_reconciliation
      return false unless reconciliation

      reconciliation.discrepancies.delete_all
      summary = calculate_and_store_discrepancies(reconciliation)
      verify_snapshot!(summary)
      reconciliation.update!(summary.merge(status: "completed", processing_token: nil))
    end

    true
  end

  private

  attr_reader :reconciliation_id, :processing_token

  def locked_reconciliation
    SellerReconciliation
      .lock
      .find_by(
        id: reconciliation_id,
        status: "processing",
        processing_token: processing_token
      )
  end

  def calculate_and_store_discrepancies(reconciliation)
    row = ApplicationRecord.connection.select_one(reconciliation_sql(reconciliation))

    {
      orders_checked: integer(row, "orders_checked"),
      matched_orders: integer(row, "matched_orders"),
      inconsistent_orders: integer(row, "inconsistent_orders"),
      missing_payment_orders: integer(row, "missing_payment_orders"),
      amount_mismatch_orders: integer(row, "amount_mismatch_orders"),
      expected_value: decimal(row, "expected_value"),
      paid_value: decimal(row, "paid_value"),
      difference: decimal(row, "difference"),
      inserted_discrepancies: integer(row, "inserted_discrepancies")
    }
  end

  def reconciliation_sql(reconciliation)
    ApplicationRecord.sanitize_sql_array([
      <<~SQL.squish,
        WITH qualified_orders AS MATERIALIZED (
          SELECT orders.id, orders.order_id AS external_order_id
          FROM orders
          WHERE orders.purchase_at >= ?
            AND orders.purchase_at < ?
            AND EXISTS (
              SELECT 1
              FROM order_items AS seller_items
              WHERE seller_items.order_id = orders.id
                AND seller_items.seller_id = ?
            )
        ),
        item_totals AS (
          SELECT order_items.order_id,
                 ROUND(SUM(order_items.price + order_items.freight_value), 2)::numeric(20, 2) AS expected_value
          FROM order_items
          INNER JOIN qualified_orders ON qualified_orders.id = order_items.order_id
          GROUP BY order_items.order_id
        ),
        payment_totals AS (
          SELECT order_payments.order_id,
                 COUNT(*) AS payment_row_count,
                 ROUND(SUM(order_payments.payment_value), 2)::numeric(20, 2) AS paid_value
          FROM order_payments
          INNER JOIN qualified_orders ON qualified_orders.id = order_payments.order_id
          GROUP BY order_payments.order_id
        ),
        calculated AS MATERIALIZED (
          SELECT qualified_orders.external_order_id,
                 item_totals.expected_value,
                 COALESCE(payment_totals.paid_value, 0)::numeric(20, 2) AS paid_value,
                 ROUND(COALESCE(payment_totals.paid_value, 0) - item_totals.expected_value, 2)::numeric(20, 2) AS difference,
                 COALESCE(payment_totals.payment_row_count, 0) AS payment_row_count
          FROM qualified_orders
          INNER JOIN item_totals ON item_totals.order_id = qualified_orders.id
          LEFT JOIN payment_totals ON payment_totals.order_id = qualified_orders.id
        ),
        inserted AS (
          INSERT INTO seller_reconciliation_discrepancies (
            seller_reconciliation_id,
            external_order_id,
            issue_type,
            expected_value,
            paid_value,
            difference,
            created_at,
            updated_at
          )
          SELECT ?,
                 external_order_id,
                 CASE WHEN payment_row_count = 0 THEN 'missing_payment' ELSE 'amount_mismatch' END,
                 expected_value,
                 paid_value,
                 difference,
                 CURRENT_TIMESTAMP,
                 CURRENT_TIMESTAMP
          FROM calculated
          WHERE payment_row_count = 0 OR difference <> 0
          RETURNING 1
        )
        SELECT COUNT(*) AS orders_checked,
               COUNT(*) FILTER (WHERE payment_row_count > 0 AND difference = 0) AS matched_orders,
               COUNT(*) FILTER (WHERE payment_row_count = 0 OR difference <> 0) AS inconsistent_orders,
               COUNT(*) FILTER (WHERE payment_row_count = 0) AS missing_payment_orders,
               COUNT(*) FILTER (WHERE payment_row_count > 0 AND difference <> 0) AS amount_mismatch_orders,
               COALESCE(SUM(expected_value), 0)::numeric(20, 2) AS expected_value,
               COALESCE(SUM(paid_value), 0)::numeric(20, 2) AS paid_value,
               (COALESCE(SUM(paid_value), 0) - COALESCE(SUM(expected_value), 0))::numeric(20, 2) AS difference,
               (SELECT COUNT(*) FROM inserted) AS inserted_discrepancies
        FROM calculated
      SQL
      utc_start(reconciliation.start_date),
      utc_start(reconciliation.end_date.next_day),
      reconciliation.seller_id,
      reconciliation.id
    ])
  end

  def verify_snapshot!(summary)
    inserted = summary.delete(:inserted_discrepancies)
    return if inserted == summary.fetch(:inconsistent_orders)

    raise InconsistentSnapshotError, "discrepancy count does not match reconciliation summary"
  end

  def utc_start(date)
    Time.utc(date.year, date.month, date.day)
  end

  def integer(row, key)
    Integer(row.fetch(key))
  end

  def decimal(row, key)
    BigDecimal(row.fetch(key).to_s)
  end
end
