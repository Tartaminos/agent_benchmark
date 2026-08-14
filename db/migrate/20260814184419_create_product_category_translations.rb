class CreateProductCategoryTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :product_category_translations do |t|
      t.string :category_name, null: false, limit: 46
      t.string :category_name_english, null: false, limit: 39

      t.timestamps
    end

    add_index :product_category_translations,
              :category_name,
              unique: true
  end
end
