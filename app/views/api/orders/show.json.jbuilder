money = ->(value) { format("%.2f", value) }
timestamp = ->(value) { value&.utc&.iso8601(3) }

items_total = @order.order_items.sum(BigDecimal("0"), &:price)
freight_total = @order.order_items.sum(BigDecimal("0"), &:freight_value)
paid_total = @order.order_payments.sum(BigDecimal("0"), &:payment_value)

json.order_id @order.order_id
json.status @order.status
json.purchase_at timestamp.call(@order.purchase_at)
json.approved_at timestamp.call(@order.approved_at)
json.delivered_carrier_at timestamp.call(@order.delivered_carrier_at)
json.delivered_customer_at timestamp.call(@order.delivered_customer_at)
json.estimated_delivery_at timestamp.call(@order.estimated_delivery_at)

json.customer do
  json.customer_id @order.customer.customer_id
  json.customer_unique_id @order.customer.customer_unique_id
  json.city @order.customer.city
  json.state @order.customer.state
end

json.items @order.order_items do |item|
  json.order_item_id item.order_item_id
  json.product_id item.product.product_id
  json.seller_id item.seller.seller_id
  json.price money.call(item.price)
  json.freight_value money.call(item.freight_value)
end

json.payments @order.order_payments do |payment|
  json.payment_sequential payment.payment_sequential
  json.payment_type payment.payment_type
  json.payment_installments payment.payment_installments
  json.payment_value money.call(payment.payment_value)
end

json.reviews @order.order_reviews do |review|
  json.review_id review.review_id
  json.score review.score
  json.comment_title review.comment_title
  json.comment_message review.comment_message
  json.creation_at timestamp.call(review.creation_at)
  json.answer_at timestamp.call(review.answer_at)
end

json.totals do
  json.items money.call(items_total)
  json.freight money.call(freight_total)
  json.order money.call(items_total + freight_total)
  json.paid money.call(paid_total)
end
