require "csv"

BASE = Rails.root.join("data", "olist")
BATCH_SIZE = 5_000

orders = Order.pluck(:order_id, :id).to_h
products = Product.pluck(:product_id, :id).to_h
sellers = Seller.pluck(:seller_id, :id).to_h

batch = []

CSV.foreach(
  BASE.join("olist_order_items_dataset.csv"),
  headers: true
) do |row|
  batch << {
    order_id: orders.fetch(row["order_id"]),
    product_id: products.fetch(row["product_id"]),
    seller_id: sellers.fetch(row["seller_id"]),
    order_item_id: row["order_item_id"],
    shipping_limit_at: row["shipping_limit_date"],
    price: row["price"],
    freight_value: row["freight_value"],
    created_at: Time.current,
    updated_at: Time.current
  }

  next unless batch.size >= BATCH_SIZE

  OrderItem.insert_all!(batch)
  batch.clear
end

OrderItem.insert_all!(batch) if batch.any?

puts "OrderItem: #{OrderItem.count}"
