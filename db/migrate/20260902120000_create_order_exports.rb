class CreateOrderExports < ActiveRecord::Migration[8.1]
  def change
    create_table :order_exports do |t|
      t.uuid :export_id, null: false
      t.string :order_status, limit: 11
      t.string :delivery_status, limit: 10
      t.string :customer_state, limit: 2
      t.date :purchase_from
      t.date :purchase_to
      t.string :status, null: false, default: "pending", limit: 10
      t.text :csv_content

      t.timestamps
    end

    add_index :order_exports, :export_id, unique: true
    add_check_constraint :order_exports,
                         "status IN ('pending', 'processing', 'completed', 'failed')",
                         name: "order_exports_status_check"
    add_check_constraint :order_exports,
                         "purchase_from IS NULL OR purchase_to IS NULL OR purchase_from <= purchase_to",
                         name: "order_exports_date_range_check"
    add_check_constraint :order_exports,
                         "(status = 'completed' AND csv_content IS NOT NULL) OR " \
                           "(status <> 'completed' AND csv_content IS NULL)",
                         name: "order_exports_csv_status_check"
  end
end
