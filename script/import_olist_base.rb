require "csv"

BASE = Rails.root.join("data", "olist")
BATCH_SIZE = 5_000

def import_csv(file, model)
  batch = []

  CSV.foreach(BASE.join(file), headers: true) do |row|
    batch << yield(row)

    next unless batch.size >= BATCH_SIZE

    model.insert_all!(batch, record_timestamps: true)
    batch.clear
  end

  model.insert_all!(batch, record_timestamps: true) if batch.any?

  puts "#{model.name}: #{model.count}"
end

import_csv("olist_customers_dataset.csv", Customer) do |row|
  {
    customer_id: row["customer_id"],
    customer_unique_id: row["customer_unique_id"],
    zip_code_prefix: row["customer_zip_code_prefix"],
    city: row["customer_city"],
    state: row["customer_state"]
  }
end

import_csv("olist_products_dataset.csv", Product) do |row|
  {
    product_id: row["product_id"],
    category_name: row["product_category_name"],
    name_length: row["product_name_lenght"],
    description_length: row["product_description_lenght"],
    photos_quantity: row["product_photos_qty"],
    weight_g: row["product_weight_g"],
    length_cm: row["product_length_cm"],
    height_cm: row["product_height_cm"],
    width_cm: row["product_width_cm"]
  }
end

import_csv("olist_sellers_dataset.csv", Seller) do |row|
  {
    seller_id: row["seller_id"],
    zip_code_prefix: row["seller_zip_code_prefix"],
    city: row["seller_city"],
    state: row["seller_state"]
  }
end

import_csv(
  "product_category_name_translation.csv",
  ProductCategoryTranslation
) do |row|
  {
    category_name: row["product_category_name"],
    category_name_english: row["product_category_name_english"]
  }
end
