class CreateSellerReconciliations < ActiveRecord::Migration[8.1]
  def change
    create_table :seller_reconciliations do |t|
      t.uuid :reconciliation_id, null: false
      t.references :seller, null: false, foreign_key: true
      t.string :status, null: false, limit: 10, default: "pending"
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.bigint :orders_checked
      t.bigint :matched_orders
      t.bigint :inconsistent_orders
      t.bigint :missing_payment_orders
      t.bigint :amount_mismatch_orders
      t.decimal :expected_value, precision: 20, scale: 2
      t.decimal :paid_value, precision: 20, scale: 2
      t.decimal :difference, precision: 20, scale: 2

      t.timestamps
    end

    add_index :seller_reconciliations, :reconciliation_id, unique: true
    add_index :seller_reconciliations, [ :seller_id, :created_at ]
    add_check_constraint :seller_reconciliations,
                         "status IN ('pending', 'processing', 'completed', 'failed')",
                         name: "seller_reconciliations_valid_status"
    add_check_constraint :seller_reconciliations,
                         "start_date <= end_date",
                         name: "seller_reconciliations_valid_date_range"
    add_check_constraint :seller_reconciliations,
                         summary_matches_status,
                         name: "seller_reconciliations_summary_matches_status"
    add_check_constraint :seller_reconciliations,
                         completed_summary_is_consistent,
                         name: "seller_reconciliations_consistent_summary"

    create_table :reconciliation_discrepancies do |t|
      t.references :seller_reconciliation, null: false, foreign_key: true
      t.string :external_order_id, null: false, limit: 32
      t.string :issue_type, null: false, limit: 20
      t.decimal :expected_value, null: false, precision: 20, scale: 2
      t.decimal :paid_value, null: false, precision: 20, scale: 2
      t.decimal :difference, null: false, precision: 20, scale: 2

      t.timestamps
    end

    add_index :reconciliation_discrepancies,
              [ :seller_reconciliation_id, :external_order_id ],
              unique: true,
              name: "index_reconciliation_discrepancies_on_reconciliation_order"
    add_check_constraint :reconciliation_discrepancies,
                         "issue_type IN ('missing_payment', 'amount_mismatch')",
                         name: "reconciliation_discrepancies_valid_issue_type"
    add_check_constraint :reconciliation_discrepancies,
                         "difference = paid_value - expected_value",
                         name: "reconciliation_discrepancies_consistent_amounts"
    add_check_constraint :reconciliation_discrepancies,
                         "issue_type <> 'missing_payment' OR paid_value = 0",
                         name: "reconciliation_discrepancies_missing_payment_zero"
  end

  private

  def summary_matches_status
    columns = %w[
      orders_checked matched_orders inconsistent_orders missing_payment_orders
      amount_mismatch_orders expected_value paid_value difference
    ]
    present = columns.map { |column| "#{column} IS NOT NULL" }.join(" AND ")
    absent = columns.map { |column| "#{column} IS NULL" }.join(" AND ")
    "(status = 'completed' AND #{present}) OR (status <> 'completed' AND #{absent})"
  end

  def completed_summary_is_consistent
    <<~SQL.squish
      status <> 'completed' OR (
        orders_checked >= 0
        AND matched_orders >= 0
        AND inconsistent_orders >= 0
        AND missing_payment_orders >= 0
        AND amount_mismatch_orders >= 0
        AND orders_checked = matched_orders + inconsistent_orders
        AND inconsistent_orders = missing_payment_orders + amount_mismatch_orders
        AND difference = paid_value - expected_value
      )
    SQL
  end
end
