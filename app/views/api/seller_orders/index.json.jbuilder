money = lambda do |value|
  integer, fraction = value.round(2).to_s("F").split(".", 2)
  "#{integer}.#{fraction.to_s.ljust(2, "0")}"
end
timestamp = ->(value) { value&.utc&.iso8601(3) }

json.seller_id @seller.seller_id
json.page @page
json.per_page @per_page
json.total_orders @total_orders
json.orders @orders do |order|
  json.order_id order.order_id
  json.status order.status
  json.purchase_at timestamp.call(order.purchase_at)
  json.item_count order.item_count
  json.items_value money.call(order.items_value)
  json.freight_value money.call(order.freight_value)
  json.total_value money.call(order.items_value + order.freight_value)
  json.products @products_by_order_id.fetch(order.internal_order_id, []) do |product|
    json.product_id product.external_product_id
    json.category_name product.category_name
  end
end
