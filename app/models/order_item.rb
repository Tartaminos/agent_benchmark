class OrderItem < ApplicationRecord
  belongs_to :order, inverse_of: :order_items
  belongs_to :product, inverse_of: :order_items
  belongs_to :seller, inverse_of: :order_items
end
