class SellerPerformanceReport < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :seller

  enum :status, STATUSES.index_with(&:itself), validate: true

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :start_date, :end_date, presence: true
  validates :csv_content, presence: true, if: :completed?
  validates :csv_content, absence: true, unless: :completed?
  validate :end_date_not_before_start_date

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def end_date_not_before_start_date
    return unless start_date && end_date && start_date > end_date

    errors.add(:end_date, "must be on or after start date")
  end
end
