class Seller < ApplicationRecord
  has_many :order_items, inverse_of: :seller
end
