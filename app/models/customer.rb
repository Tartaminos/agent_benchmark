class Customer < ApplicationRecord
  has_many :orders, inverse_of: :customer
end
