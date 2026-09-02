class SellerReconciliation < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze
  SUMMARY_ATTRIBUTES = %i[
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
  has_many :discrepancies,
           class_name: "SellerReconciliationDiscrepancy",
           dependent: :delete_all,
           inverse_of: :seller_reconciliation

  before_validation :assign_reconciliation_id, on: :create

  attr_readonly :reconciliation_id, :seller_id, :start_date, :end_date

  validates :reconciliation_id, presence: true, uniqueness: true
  validates :start_date, :end_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_date_not_before_start_date
  validate :summary_matches_status
  validate :processing_token_matches_status

  private

  def assign_reconciliation_id
    self.reconciliation_id ||= SecureRandom.uuid
  end

  def end_date_not_before_start_date
    return unless start_date && end_date && start_date > end_date

    errors.add(:end_date, "must be on or after start_date")
  end

  def summary_matches_status
    values = SUMMARY_ATTRIBUTES.map { |attribute| public_send(attribute) }

    if status == "completed"
      errors.add(:base, "completed reconciliation requires a complete summary") if values.any?(&:nil?)
    elsif values.any?
      errors.add(:base, "summary must be absent unless completed")
    end
  end

  def processing_token_matches_status
    token_present = processing_token.present?
    return if (status == "processing") == token_present

    errors.add(:processing_token, "must be present only while processing")
  end
end
