class CreateSellers < ActiveRecord::Migration[8.1]
  def change
    create_table :sellers do |t|
      t.string :seller_id, null: false, limit: 32
      t.string :zip_code_prefix, null: false, limit: 5
      t.string :city, null: false, limit: 40
      t.string :state, null: false, limit: 2

      t.timestamps
    end

    add_index :sellers, :seller_id, unique: true
  end
end
