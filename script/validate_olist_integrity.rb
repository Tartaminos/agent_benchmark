EXPECTED_COUNTS = {
  Customer => 99_441,
  Product => 32_951,
  Seller => 3_095,
  Order => 99_441,
  OrderItem => 112_650,
  OrderPayment => 103_886,
  OrderReview => 99_224,
  Geolocation => 1_000_163,
  ProductCategoryTranslation => 71
}.freeze

errors = []

puts "=== COUNTS ==="

EXPECTED_COUNTS.each do |model, expected|
  actual = model.count
  status = actual == expected ? "PASS" : "FAIL"

  puts "#{status} #{model.name}: #{actual} / #{expected}"

  errors << "#{model.name} count" unless actual == expected
end

puts "\n=== UNIQUE KEYS ==="

unique_checks = {
  "Customer.customer_id" => [
    Customer.count,
    Customer.distinct.count(:customer_id)
  ],

  "Product.product_id" => [
    Product.count,
    Product.distinct.count(:product_id)
  ],

  "Seller.seller_id" => [
    Seller.count,
    Seller.distinct.count(:seller_id)
  ],

  "Order.order_id" => [
    Order.count,
    Order.distinct.count(:order_id)
  ],

  "ProductCategoryTranslation.category_name" => [
    ProductCategoryTranslation.count,
    ProductCategoryTranslation.distinct.count(:category_name)
  ]
}

unique_checks.each do |name, (total, unique)|
  status = total == unique ? "PASS" : "FAIL"

  puts "#{status} #{name}: #{unique} unique / #{total}"

  errors << "#{name} uniqueness" unless total == unique
end

puts "\n=== COMPOSITE KEYS ==="

order_item_duplicates = ActiveRecord::Base.connection.select_value(<<~SQL).to_i
  SELECT COUNT(*)
  FROM (
    SELECT order_id, order_item_id
    FROM order_items
    GROUP BY order_id, order_item_id
    HAVING COUNT(*) > 1
  ) duplicates
SQL

payment_duplicates = ActiveRecord::Base.connection.select_value(<<~SQL).to_i
  SELECT COUNT(*)
  FROM (
    SELECT order_id, payment_sequential
    FROM order_payments
    GROUP BY order_id, payment_sequential
    HAVING COUNT(*) > 1
  ) duplicates
SQL

[
  ["OrderItem order_id + order_item_id", order_item_duplicates],
  ["OrderPayment order_id + payment_sequential", payment_duplicates]
].each do |name, duplicates|
  status = duplicates.zero? ? "PASS" : "FAIL"

  puts "#{status} #{name}: #{duplicates} duplicate groups"

  errors << "#{name} duplicates" unless duplicates.zero?
end

puts "\n=== FOREIGN KEYS / ORPHANS ==="

orphan_checks = {
  "Order -> Customer" => <<~SQL,
    SELECT COUNT(*)
    FROM orders o
    LEFT JOIN customers c ON c.id = o.customer_id
    WHERE c.id IS NULL
  SQL

  "OrderItem -> Order" => <<~SQL,
    SELECT COUNT(*)
    FROM order_items oi
    LEFT JOIN orders o ON o.id = oi.order_id
    WHERE o.id IS NULL
  SQL

  "OrderItem -> Product" => <<~SQL,
    SELECT COUNT(*)
    FROM order_items oi
    LEFT JOIN products p ON p.id = oi.product_id
    WHERE p.id IS NULL
  SQL

  "OrderItem -> Seller" => <<~SQL,
    SELECT COUNT(*)
    FROM order_items oi
    LEFT JOIN sellers s ON s.id = oi.seller_id
    WHERE s.id IS NULL
  SQL

  "OrderPayment -> Order" => <<~SQL,
    SELECT COUNT(*)
    FROM order_payments op
    LEFT JOIN orders o ON o.id = op.order_id
    WHERE o.id IS NULL
  SQL

  "OrderReview -> Order" => <<~SQL
    SELECT COUNT(*)
    FROM order_reviews r
    LEFT JOIN orders o ON o.id = r.order_id
    WHERE o.id IS NULL
  SQL
}

orphan_checks.each do |name, sql|
  count = ActiveRecord::Base.connection.select_value(sql).to_i
  status = count.zero? ? "PASS" : "FAIL"

  puts "#{status} #{name}: #{count} orphan records"

  errors << "#{name} orphans" unless count.zero?
end

puts "\n=== RESULT ==="

if errors.empty?
  puts "PASS — Olist benchmark database is consistent."
else
  puts "FAIL — #{errors.size} problem(s) found:"
  errors.each { |error| puts "- #{error}" }
  exit 1
end
