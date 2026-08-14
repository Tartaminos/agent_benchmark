class CreateGeolocations < ActiveRecord::Migration[8.1]
  def change
    create_table :geolocations do |t|
      t.string :zip_code_prefix, null: false, limit: 5

      t.decimal :latitude,
                precision: 17,
                scale: 14,
                null: false

      t.decimal :longitude,
                precision: 17,
                scale: 14,
                null: false

      t.string :city, null: false, limit: 38
      t.string :state, null: false, limit: 2

      t.timestamps
    end

    add_index :geolocations, :zip_code_prefix
  end
end
