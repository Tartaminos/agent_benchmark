class CreateOrderPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :order_payments do |t|
      t.references :order, null: false, foreign_key: true
      t.integer :payment_sequential, null: false
      t.string :payment_type, null: false, limit: 11
      t.integer :payment_installments, null: false
      t.decimal :payment_value, precision: 12, scale: 2, null: false

      t.timestamps
    end

    add_index :order_payments,
              [:order_id, :payment_sequential],
              unique: true
  end
end
