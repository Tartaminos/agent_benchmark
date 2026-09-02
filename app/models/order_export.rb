class OrderExport < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze
  FILTER_ATTRIBUTES = %w[order_status delivery_status customer_state purchase_from purchase_to].freeze

  attr_readonly :export_id, *FILTER_ATTRIBUTES

  before_validation :assign_export_id, on: :create

  validates :export_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :order_status, inclusion: { in: Order::ORDER_STATUSES }, allow_nil: true
  validates :delivery_status, inclusion: { in: Order::DELIVERY_STATUSES }, allow_nil: true
  validates :customer_state, inclusion: { in: Customer::STATES }, allow_nil: true
  validate :purchase_range_is_ordered
  validate :filter_snapshot_is_immutable, on: :update
  validate :csv_content_matches_status

  private

  def assign_export_id
    self.export_id ||= SecureRandom.uuid
  end

  def purchase_range_is_ordered
    return unless purchase_from && purchase_to && purchase_from > purchase_to

    errors.add(:purchase_to, "must be on or after purchase_from")
  end

  def filter_snapshot_is_immutable
    changed_filter = FILTER_ATTRIBUTES.find { |attribute| will_save_change_to_attribute?(attribute) }
    errors.add(changed_filter, "cannot be changed") if changed_filter
  end

  def csv_content_matches_status
    if status == "completed"
      errors.add(:csv_content, "must be present when completed") if csv_content.nil?
    elsif !csv_content.nil?
      errors.add(:csv_content, "must be absent unless completed")
    end
  end
end
