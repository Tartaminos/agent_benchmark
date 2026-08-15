class Order < ApplicationRecord
  belongs_to :customer

  has_many :order_items, -> { order(order_item_id: :asc) }
  has_many :order_payments, -> { order(payment_sequential: :asc) }
  has_many :order_reviews
end
