class Order < ApplicationRecord
  ORDER_STATUSES = %w[approved canceled created delivered invoiced processing shipped unavailable].freeze
  DELIVERY_STATUSES = %w[pending on_time late].freeze

  belongs_to :customer

  has_many :order_items
  has_many :order_payments
  has_many :order_reviews

  scope :delivery_pending, -> { where(arel_table[:delivered_customer_at].eq(nil)) }
  scope :delivery_on_time, -> do
    where(arel_table[:delivered_customer_at].lteq(arel_table[:estimated_delivery_at]))
  end
  scope :delivery_late, -> do
    where(arel_table[:delivered_customer_at].gt(arel_table[:estimated_delivery_at]))
  end

  def self.with_delivery_status(status)
    case status
    when nil then all
    when "pending" then delivery_pending
    when "on_time" then delivery_on_time
    when "late" then delivery_late
    else raise ArgumentError, "unsupported delivery status"
    end
  end

  def delivery_status
    return "pending" unless delivered_customer_at
    return "on_time" if delivered_customer_at <= estimated_delivery_at

    "late"
  end
end
