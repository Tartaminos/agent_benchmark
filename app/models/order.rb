class Order < ApplicationRecord
  belongs_to :customer, inverse_of: :orders
  has_many :order_items, -> { order(order_item_id: :asc) }, inverse_of: :order
  has_many :order_payments, -> { order(payment_sequential: :asc) }, inverse_of: :order
  has_many :order_reviews,
           -> { order(creation_at: :asc, review_id: :asc, id: :asc) },
           inverse_of: :order
end
