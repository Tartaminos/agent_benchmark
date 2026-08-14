require "csv"

BASE = Rails.root.join("data", "olist")
BATCH_SIZE = 5_000

orders = Order.pluck(:order_id, :id).to_h

batch = []

CSV.foreach(
  BASE.join("olist_order_payments_dataset.csv"),
  headers: true
) do |row|
  batch << {
    order_id: orders.fetch(row["order_id"]),
    payment_sequential: row["payment_sequential"],
    payment_type: row["payment_type"],
    payment_installments: row["payment_installments"],
    payment_value: row["payment_value"],
    created_at: Time.current,
    updated_at: Time.current
  }

  next unless batch.size >= BATCH_SIZE

  OrderPayment.insert_all!(batch)
  batch.clear
end

OrderPayment.insert_all!(batch) if batch.any?

puts "OrderPayment: #{OrderPayment.count}"
