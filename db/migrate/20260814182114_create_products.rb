class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :product_id, null: false, limit: 32
      t.string :category_name, limit: 46

      t.integer :name_length
      t.integer :description_length
      t.integer :photos_quantity
      t.integer :weight_g
      t.integer :length_cm
      t.integer :height_cm
      t.integer :width_cm

      t.timestamps
    end

    add_index :products, :product_id, unique: true
  end
end
