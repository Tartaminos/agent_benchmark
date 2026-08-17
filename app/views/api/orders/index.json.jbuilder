timestamp = ->(value) { value&.utc&.iso8601(3) }

json.page @page
json.per_page @per_page
json.total_orders @total_orders
json.total_pages @total_pages
json.orders @orders do |order|
  json.order_id order.order_id
  json.status order.status
  json.purchase_at timestamp.call(order.purchase_at)
  json.estimated_delivery_at timestamp.call(order.estimated_delivery_at)
  json.delivered_customer_at timestamp.call(order.delivered_customer_at)
  json.delivery_status order.delivery_status
end
