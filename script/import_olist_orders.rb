require "csv"

BASE = Rails.root.join("data", "olist")
BATCH_SIZE = 5_000

customers = Customer.pluck(:customer_id, :id).to_h

batch = []

CSV.foreach(
  BASE.join("olist_orders_dataset.csv"),
  headers: true
) do |row|

  customer_id = customers.fetch(row["customer_id"])

  batch << {
    order_id: row["order_id"],
    customer_id: customer_id,
    status: row["order_status"],
    purchase_at: row["order_purchase_timestamp"],
    approved_at: row["order_approved_at"].presence,
    delivered_carrier_at: row["order_delivered_carrier_date"].presence,
    delivered_customer_at: row["order_delivered_customer_date"].presence,
    estimated_delivery_at: row["order_estimated_delivery_date"],
    created_at: Time.current,
    updated_at: Time.current
  }

  next unless batch.size >= BATCH_SIZE

  Order.insert_all!(batch)
  batch.clear
end

Order.insert_all!(batch) if batch.any?

puts "Order: #{Order.count}"
