require "csv"
require "bigdecimal/util"

FILES = {
  customers: "olist_customers_dataset.csv",
  products: "olist_products_dataset.csv",
  sellers: "olist_sellers_dataset.csv",
  orders: "olist_orders_dataset.csv",
  order_items: "olist_order_items_dataset.csv",
  order_payments: "olist_order_payments_dataset.csv",
  order_reviews: "olist_order_reviews_dataset.csv",
  geolocations: "olist_geolocation_dataset.csv",
  product_category_translations: "product_category_name_translation.csv"
}

base = Rails.root.join("data", "olist")

FILES.each do |name, filename|
  table = CSV.read(base.join(filename), headers: true)

  puts "\n=== #{name} ==="

  table.headers.each do |column|
    values = table[column]

    blank_count = values.count { |value| value.nil? || value.strip.empty? }

    non_blank = values.reject do |value|
      value.nil? || value.strip.empty?
    end

    max_length = non_blank.map(&:length).max || 0

    puts "#{column}:"
    puts "  blanks: #{blank_count}"
    puts "  max_length: #{max_length}"
  end
end

puts "\n=== NUMERIC RANGES ==="

items = CSV.read(
  base.join("olist_order_items_dataset.csv"),
  headers: true
)

%w[price freight_value].each do |column|
  values = items[column]
    .reject { |value| value.nil? || value.empty? }
    .map(&:to_d)

  puts "#{column}:"
  puts "  min: #{values.min.to_s('F')}"
  puts "  max: #{values.max.to_s('F')}"
end



puts "\n=== PAYMENT NUMERIC RANGES ==="

payments = CSV.read(
  base.join("olist_order_payments_dataset.csv"),
  headers: true
)

%w[payment_sequential payment_installments payment_value].each do |column|
  values = payments[column]
    .reject { |value| value.nil? || value.empty? }
    .map(&:to_d)

  puts "#{column}:"
  puts "  min: #{values.min.to_s('F')}"
  puts "  max: #{values.max.to_s('F')}"
end

puts "\n=== GEOLOCATION NUMERIC RANGES ==="

geolocations = CSV.read(
  base.join("olist_geolocation_dataset.csv"),
  headers: true
)

%w[geolocation_lat geolocation_lng].each do |column|
  values = geolocations[column]
    .reject { |value| value.nil? || value.empty? }
    .map(&:to_d)

  puts "#{column}:"
  puts "  min: #{values.min.to_s('F')}"
  puts "  max: #{values.max.to_s('F')}"
end
