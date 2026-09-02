class SellerReconciliationGenerator
  GENERATE_SQL = <<~SQL.freeze
    WITH qualifying_orders AS MATERIALIZED (
      SELECT DISTINCT orders.id, orders.order_id
      FROM orders
      INNER JOIN order_items AS seller_items ON seller_items.order_id = orders.id
      WHERE seller_items.seller_id = :seller_id
        AND orders.purchase_at >= :start_date
        AND orders.purchase_at < :exclusive_end_date
    ),
    item_totals AS MATERIALIZED (
      SELECT
        order_items.order_id,
        SUM(order_items.price + order_items.freight_value)::numeric AS expected_value
      FROM order_items
      INNER JOIN qualifying_orders ON qualifying_orders.id = order_items.order_id
      GROUP BY order_items.order_id
    ),
    payment_totals AS MATERIALIZED (
      SELECT
        order_payments.order_id,
        COUNT(*) AS payment_count,
        SUM(order_payments.payment_value)::numeric AS paid_value
      FROM order_payments
      INNER JOIN qualifying_orders ON qualifying_orders.id = order_payments.order_id
      GROUP BY order_payments.order_id
    ),
    reconciled AS MATERIALIZED (
      SELECT
        qualifying_orders.order_id AS external_order_id,
        ROUND(item_totals.expected_value, 2) AS expected_value,
        ROUND(COALESCE(payment_totals.paid_value, 0), 2) AS paid_value,
        COALESCE(payment_totals.payment_count, 0) AS payment_count,
        ROUND(COALESCE(payment_totals.paid_value, 0) - item_totals.expected_value, 2) AS difference
      FROM qualifying_orders
      INNER JOIN item_totals ON item_totals.order_id = qualifying_orders.id
      LEFT JOIN payment_totals ON payment_totals.order_id = qualifying_orders.id
    ),
    inserted AS (
      INSERT INTO reconciliation_discrepancies (
        seller_reconciliation_id,
        external_order_id,
        issue_type,
        expected_value,
        paid_value,
        difference,
        created_at,
        updated_at
      )
      SELECT
        :reconciliation_id,
        reconciled.external_order_id,
        CASE
          WHEN reconciled.payment_count = 0 THEN 'missing_payment'
          ELSE 'amount_mismatch'
        END,
        reconciled.expected_value,
        reconciled.paid_value,
        reconciled.difference,
        :current_time,
        :current_time
      FROM reconciled
      WHERE reconciled.payment_count = 0 OR reconciled.difference <> 0
      RETURNING issue_type
    ),
    summary AS (
      SELECT
        COUNT(*) AS orders_checked,
        COUNT(*) FILTER (WHERE payment_count > 0 AND difference = 0) AS matched_orders,
        COUNT(*) FILTER (WHERE payment_count = 0 OR difference <> 0) AS inconsistent_orders,
        COUNT(*) FILTER (WHERE payment_count = 0) AS missing_payment_orders,
        COUNT(*) FILTER (WHERE payment_count > 0 AND difference <> 0) AS amount_mismatch_orders,
        ROUND(COALESCE(SUM(expected_value), 0), 2) AS expected_value,
        ROUND(COALESCE(SUM(paid_value), 0), 2) AS paid_value
      FROM reconciled
    ),
    inserted_summary AS (
      SELECT COUNT(*) AS discrepancy_count FROM inserted
    )
    UPDATE seller_reconciliations
    SET
      status = 'completed',
      orders_checked = summary.orders_checked,
      matched_orders = summary.matched_orders,
      inconsistent_orders = summary.inconsistent_orders,
      missing_payment_orders = summary.missing_payment_orders,
      amount_mismatch_orders = summary.amount_mismatch_orders,
      expected_value = summary.expected_value,
      paid_value = summary.paid_value,
      difference = summary.paid_value - summary.expected_value,
      updated_at = :current_time
    FROM summary, inserted_summary
    WHERE seller_reconciliations.id = :reconciliation_id
      AND seller_reconciliations.status = 'processing'
      AND inserted_summary.discrepancy_count = summary.inconsistent_orders
  SQL

  def initialize(reconciliation)
    @reconciliation = reconciliation
  end

  def call
    SellerReconciliation.transaction(requires_new: true) do
      affected_rows = SellerReconciliation.connection.update(
        generation_sql,
        "Generate seller reconciliation"
      )
      unless affected_rows == 1
        raise ActiveRecord::RecordNotSaved, "reconciliation could not be published"
      end
    end

    reconciliation.reload
  end

  private

  attr_reader :reconciliation

  def generation_sql
    SellerReconciliation.sanitize_sql_array([
      GENERATE_SQL,
      {
        seller_id: reconciliation.seller_id,
        start_date: reconciliation.start_date,
        exclusive_end_date: reconciliation.end_date.next_day,
        reconciliation_id: reconciliation.id,
        current_time: Time.current
      }
    ])
  end
end
