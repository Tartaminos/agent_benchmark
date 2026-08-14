require "csv"

BASE = Rails.root.join("data", "olist")
BATCH_SIZE = 5_000

def flush_batch(model, batch)
  return if batch.empty?

  model.insert_all!(batch, record_timestamps: true)
  batch.clear
end

puts "Importing OrderReviews..."

orders = Order.pluck(:order_id, :id).to_h
batch = []

CSV.foreach(
  BASE.join("olist_order_reviews_dataset.csv"),
  headers: true
) do |row|
  batch << {
    order_id: orders.fetch(row["order_id"]),
    review_id: row["review_id"],
    score: row["review_score"],
    comment_title: row["review_comment_title"].presence,
    comment_message: row["review_comment_message"].presence,
    creation_at: row["review_creation_date"],
    answer_at: row["review_answer_timestamp"]
  }

  flush_batch(OrderReview, batch) if batch.size >= BATCH_SIZE
end

flush_batch(OrderReview, batch)

puts "OrderReview: #{OrderReview.count}"

puts "Importing Geolocations..."

batch = []

CSV.foreach(
  BASE.join("olist_geolocation_dataset.csv"),
  headers: true
) do |row|
  batch << {
    zip_code_prefix: row["geolocation_zip_code_prefix"],
    latitude: row["geolocation_lat"],
    longitude: row["geolocation_lng"],
    city: row["geolocation_city"],
    state: row["geolocation_state"]
  }

  flush_batch(Geolocation, batch) if batch.size >= BATCH_SIZE
end

flush_batch(Geolocation, batch)

puts "Geolocation: #{Geolocation.count}"

puts "Import finished."
