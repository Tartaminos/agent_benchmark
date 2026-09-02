class CreateOrderExports < ActiveRecord::Migration[8.1]
  def change
    create_table :order_exports do |t|
      t.uuid :export_id, null: false
      t.string :status, null: false, limit: 10, default: "pending"
      t.jsonb :filters, null: false, default: {}

      t.timestamps
    end

    add_index :order_exports, :export_id, unique: true
    add_index :orders, [ :purchase_at, :order_id ], name: "index_orders_on_purchase_at_and_order_id"
    add_check_constraint :order_exports,
                         "status IN ('pending', 'processing', 'completed', 'failed')",
                         name: "order_exports_valid_status"
  end
end
