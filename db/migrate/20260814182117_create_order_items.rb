class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order,
                  null: false,
                  foreign_key: true

      t.references :product,
                  null: false,
                  foreign_key: true

      t.references :seller,
                  null: false,
                  foreign_key: true

      t.integer :order_item_id, null: false
      t.datetime :shipping_limit_at, null: false

      t.decimal :price,
                precision: 10,
                scale: 2,
                null: false

      t.decimal :freight_value,
                precision: 10,
                scale: 2,
                null: false

      t.timestamps
    end

    add_index :order_items,
              [:order_id, :order_item_id],
              unique: true
      end
end
