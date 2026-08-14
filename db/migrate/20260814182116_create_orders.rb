class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :order_id, null: false, limit: 32

      t.references :customer,
                  null: false,
                  foreign_key: true

      t.string :status, null: false, limit: 11

      t.datetime :purchase_at, null: false
      t.datetime :approved_at
      t.datetime :delivered_carrier_at
      t.datetime :delivered_customer_at
      t.datetime :estimated_delivery_at, null: false

      t.timestamps
    end

    add_index :orders, :order_id, unique: true
  end
end
