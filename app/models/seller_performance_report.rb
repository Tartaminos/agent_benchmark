class SellerPerformanceReport < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :seller

  before_validation :assign_report_id, on: :create

  validates :report_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :start_date, :end_date, presence: true
  validate :date_range_is_ordered
  validate :csv_matches_status
  validate :valid_status_transition, on: :update

  def begin_processing!
    return true if processing?
    return false unless pending?

    transitioned = self.class.where(id: id, status: "pending").update_all(
      status: "processing",
      updated_at: Time.current
    )
    reload
    transitioned == 1 || processing?
  end

  def complete!(generated_csv)
    transitioned = self.class.where(id: id, status: "processing").update_all(
      status: "completed",
      csv_data: generated_csv,
      updated_at: Time.current
    )
    reload
    transitioned == 1
  end

  def fail!
    transitioned = self.class.where(id: id, status: %w[pending processing]).update_all(
      status: "failed",
      csv_data: nil,
      updated_at: Time.current
    )
    reload
    transitioned == 1
  end

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  private

  def assign_report_id
    self.report_id ||= SecureRandom.uuid
  end

  def date_range_is_ordered
    return if start_date.blank? || end_date.blank? || start_date <= end_date

    errors.add(:start_date, "must be on or before end_date")
  end

  def csv_matches_status
    if completed? && csv_data.nil?
      errors.add(:csv_data, "must be present for a completed report")
    elsif !completed? && csv_data.present?
      errors.add(:csv_data, "must be absent until the report is completed")
    end
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
