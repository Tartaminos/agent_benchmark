class OrderReview < ApplicationRecord
  belongs_to :order, inverse_of: :order_reviews
end
