class CreateSellerReconciliations < ActiveRecord::Migration[8.1]
  SUMMARY_COLUMNS = %w[
    orders_checked
    matched_orders
    inconsistent_orders
    missing_payment_orders
    amount_mismatch_orders
    expected_value
    paid_value
    difference
  ].freeze

  def change
    create_table :seller_reconciliations do |t|
      t.uuid :reconciliation_id, null: false
      t.references :seller, null: false, foreign_key: true
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, null: false, default: "pending", limit: 10
      t.uuid :processing_token
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
    add_check_constraint :seller_reconciliations,
                         "status IN ('pending', 'processing', 'completed', 'failed')",
                         name: "seller_reconciliations_status_check"
    add_check_constraint :seller_reconciliations,
                         "start_date <= end_date",
                         name: "seller_reconciliations_date_range_check"
    add_check_constraint :seller_reconciliations,
                         "orders_checked >= 0 AND matched_orders >= 0 AND " \
                           "inconsistent_orders >= 0 AND missing_payment_orders >= 0 AND " \
                           "amount_mismatch_orders >= 0",
                         name: "seller_reconciliations_nonnegative_counts_check"
    add_check_constraint :seller_reconciliations,
                         "orders_checked = matched_orders + inconsistent_orders AND " \
                           "inconsistent_orders = missing_payment_orders + amount_mismatch_orders",
                         name: "seller_reconciliations_count_invariants_check"
    add_check_constraint :seller_reconciliations,
                         "expected_value >= 0 AND paid_value >= 0 AND " \
                           "difference = paid_value - expected_value",
                         name: "seller_reconciliations_money_invariants_check"

    summary_present = SUMMARY_COLUMNS.map { |column| "#{column} IS NOT NULL" }.join(" AND ")
    summary_absent = SUMMARY_COLUMNS.map { |column| "#{column} IS NULL" }.join(" AND ")
    add_check_constraint :seller_reconciliations,
                         "(status = 'completed' AND #{summary_present} AND processing_token IS NULL) OR " \
                           "(status <> 'completed' AND #{summary_absent})",
                         name: "seller_reconciliations_summary_status_check"
    add_check_constraint :seller_reconciliations,
                         "(status = 'processing') = (processing_token IS NOT NULL)",
                         name: "seller_reconciliations_processing_token_check"

    create_table :seller_reconciliation_discrepancies do |t|
      t.references :seller_reconciliation,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: false
      t.string :external_order_id, null: false, limit: 32
      t.string :issue_type, null: false, limit: 15
      t.decimal :expected_value, null: false, precision: 20, scale: 2
      t.decimal :paid_value, null: false, precision: 20, scale: 2
      t.decimal :difference, null: false, precision: 20, scale: 2

      t.timestamps
    end

    add_index :seller_reconciliation_discrepancies,
              %i[seller_reconciliation_id external_order_id],
              unique: true,
              name: "idx_reconciliation_discrepancies_order"
    add_check_constraint :seller_reconciliation_discrepancies,
                         "issue_type IN ('missing_payment', 'amount_mismatch')",
                         name: "reconciliation_discrepancies_issue_type_check"
    add_check_constraint :seller_reconciliation_discrepancies,
                         "expected_value >= 0 AND paid_value >= 0 AND " \
                           "difference = paid_value - expected_value",
                         name: "reconciliation_discrepancies_money_check"
    add_check_constraint :seller_reconciliation_discrepancies,
                         "(issue_type = 'missing_payment' AND paid_value = 0 AND " \
                           "difference = -expected_value) OR " \
                           "(issue_type = 'amount_mismatch' AND difference <> 0)",
                         name: "reconciliation_discrepancies_classification_check"
  end
end
