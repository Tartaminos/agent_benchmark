require "csv"
require "set"

checks = {
  "olist_customers_dataset.csv" => [%w[customer_id], %w[customer_unique_id]],
  "olist_geolocation_dataset.csv" => [%w[geolocation_zip_code_prefix]],
  "olist_order_items_dataset.csv" => [%w[order_id order_item_id]],
  "olist_order_payments_dataset.csv" => [%w[order_id payment_sequential]],
  "olist_order_reviews_dataset.csv" => [%w[review_id], %w[order_id]],
  "olist_orders_dataset.csv" => [%w[order_id], %w[customer_id]],
  "olist_products_dataset.csv" => [%w[product_id]],
  "olist_sellers_dataset.csv" => [%w[seller_id]],
  "product_category_name_translation.csv" => [%w[product_category_name]]
}

base = Rails.root.join("data", "olist")

checks.each do |file, keys|
  rows = CSV.foreach(base.join(file), headers: true).to_a

  puts "\n=== #{file} ==="
  puts "Rows: #{rows.size}"

  keys.each do |columns|
    values = rows.map { |row| columns.map { |column| row[column] } }

    puts "#{columns.join(' + ')}:"
    puts "  unique: #{values.uniq.size}"
    puts "  duplicates: #{values.size - values.uniq.size}"
  end
end
