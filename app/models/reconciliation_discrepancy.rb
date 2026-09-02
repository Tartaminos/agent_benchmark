class ReconciliationDiscrepancy < ApplicationRecord
  ISSUE_TYPES = %w[missing_payment amount_mismatch].freeze

  belongs_to :seller_reconciliation

  validates :external_order_id, presence: true,
                                uniqueness: { scope: :seller_reconciliation_id }
  validates :issue_type, inclusion: { in: ISSUE_TYPES }
  validates :expected_value, :paid_value, :difference, presence: true
end
