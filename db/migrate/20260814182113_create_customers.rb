class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :customer_id, null: false, limit: 32
      t.string :customer_unique_id, null: false, limit: 32
      t.string :zip_code_prefix, null: false, limit: 5
      t.string :city, null: false, limit: 32
      t.string :state, null: false, limit: 2

      t.timestamps
    end

    add_index :customers, :customer_id, unique: true
    add_index :customers, :customer_unique_id
  end
end
