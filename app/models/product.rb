class Product < ApplicationRecord
  has_many :order_items, inverse_of: :product
end
