class SellerPerformanceReport < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :seller

  before_validation :assign_report_id, on: :create

  validates :report_id, presence: true, uniqueness: true
  validates :start_date, :end_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_date_not_before_start_date
  validate :csv_content_matches_status

  private

  def assign_report_id
    self.report_id ||= SecureRandom.uuid
  end

  def end_date_not_before_start_date
    return unless start_date && end_date && start_date > end_date

    errors.add(:end_date, "must be on or after start_date")
  end

  def csv_content_matches_status
    if status == "completed"
      errors.add(:csv_content, "must be present when completed") if csv_content.blank?
    elsif !csv_content.nil?
      errors.add(:csv_content, "must be absent unless completed")
    end
  end
end
