class Order < ApplicationRecord
  DELIVERY_STATUSES = %w[pending on_time late].freeze

  belongs_to :customer

  has_many :order_items
  has_many :order_payments
  has_many :order_reviews

  scope :with_delivery_status, ->(delivery_status) do
    case delivery_status
    when nil
      all
    when "pending"
      where(delivered_customer_at: nil)
    when "on_time"
      where("orders.delivered_customer_at <= orders.estimated_delivery_at")
    when "late"
      where("orders.delivered_customer_at > orders.estimated_delivery_at")
    else
      none
    end
  end

  def delivery_status
    return "pending" unless delivered_customer_at
    return "on_time" if delivered_customer_at <= estimated_delivery_at

    "late"
  end
end
