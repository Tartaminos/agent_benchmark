class SellerReconciliation < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze
  SUMMARY_ATTRIBUTES = %w[
    orders_checked
    matched_orders
    inconsistent_orders
    missing_payment_orders
    amount_mismatch_orders
    expected_value
    paid_value
    difference
  ].freeze

  belongs_to :seller
  has_many :reconciliation_discrepancies, dependent: :delete_all

  before_validation :assign_reconciliation_id, on: :create

  validates :reconciliation_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :start_date, :end_date, presence: true
  validate :date_range_is_ordered
  validate :summary_matches_status
  validate :summary_counts_are_consistent
  validate :valid_status_transition, on: :update

  def claim_for_processing!
    transitioned = self.class.where(id: id, status: "pending").update_all(
      status: "processing",
      updated_at: Time.current
    )
    reload
    transitioned == 1
  end

  def fail!
    transitioned = self.class.where(id: id, status: %w[pending processing]).update_all(
      status: "failed",
      updated_at: Time.current
    )
    reload
    transitioned == 1
  end

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  private

  def assign_reconciliation_id
    self.reconciliation_id ||= SecureRandom.uuid
  end

  def date_range_is_ordered
    return if start_date.blank? || end_date.blank? || start_date <= end_date

    errors.add(:start_date, "must be on or before end_date")
  end

  def summary_matches_status
    values = SUMMARY_ATTRIBUTES.map { |attribute| public_send(attribute) }
    if completed? && values.any?(&:nil?)
      errors.add(:base, "summary must be present for a completed reconciliation")
    elsif !completed? && values.any?(&:present?)
      errors.add(:base, "summary must be absent until reconciliation is completed")
    end
  end

  def summary_counts_are_consistent
    return unless completed? && SUMMARY_ATTRIBUTES.none? { |attribute| public_send(attribute).nil? }

    unless orders_checked == matched_orders + inconsistent_orders
      errors.add(:orders_checked, "must equal matched and inconsistent orders")
    end
    unless inconsistent_orders == missing_payment_orders + amount_mismatch_orders
      errors.add(:inconsistent_orders, "must equal discrepancy type counts")
    end
    errors.add(:difference, "must equal paid minus expected value") unless difference == paid_value - expected_value
  end

  def valid_status_transition
    return unless will_save_change_to_status?

    allowed_statuses = {
      "pending" => %w[processing failed],
      "processing" => %w[completed failed],
      "completed" => [],
      "failed" => []
    }
    previous_status = status_in_database
    return if allowed_statuses.fetch(previous_status, []).include?(status)

    errors.add(:status, "cannot transition from #{previous_status} to #{status}")
  end
end
