class Order < ApplicationRecord
  DELIVERY_STATUSES = %w[pending on_time late].freeze
  DELIVERY_STATUS_SQL = <<~SQL.squish.freeze
    CASE
      WHEN orders.delivered_customer_at IS NULL THEN 'pending'
      WHEN orders.delivered_customer_at <= orders.estimated_delivery_at THEN 'on_time'
      ELSE 'late'
    END
  SQL

  belongs_to :customer
  has_many :order_items
  has_many :order_payments
  has_many :order_reviews

  scope :for_delivery_status, ->(delivery_status) {
    where("#{DELIVERY_STATUS_SQL} = ?", delivery_status)
  }

  scope :with_delivery_status, -> {
    select("orders.*", "#{DELIVERY_STATUS_SQL} AS delivery_status")
  }
end
