money = ->(value) { format("%.2f", value) }
timestamp = ->(value) { value.utc.iso8601(3) }

json.seller_id @seller.seller_id
json.page @page
json.per_page @per_page
json.total_orders @total_orders
json.orders @orders do |order|
  items_value = BigDecimal(order.items_value.to_s)
  freight_value = BigDecimal(order.freight_value.to_s)

  json.order_id order.order_id
  json.status order.status
  json.purchase_at timestamp.call(order.purchase_at)
  json.item_count order.item_count.to_i
  json.items_value money.call(items_value)
  json.freight_value money.call(freight_value)
  json.total_value money.call(items_value + freight_value)
  json.products @products_by_order_id.fetch(order.id, []) do |product|
    json.product_id product.external_product_id
    json.category_name product.product_category_name
  end
end
