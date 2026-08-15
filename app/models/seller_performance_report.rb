class SellerPerformanceReport < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :seller

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :start_date, :end_date, presence: true
  validates :csv_data, presence: true, if: :completed?
  validates :csv_data, absence: true, unless: :completed?
  validate :date_range_is_ordered

  def completed?
    status == "completed"
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def date_range_is_ordered
    return unless start_date && end_date
    return if start_date <= end_date

    errors.add(:end_date, "must be on or after start date")
  end
end
