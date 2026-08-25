class OrderPayment < ApplicationRecord
  belongs_to :order, inverse_of: :order_payments
end
