class OrderExport < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  has_one_attached :file

  before_validation :assign_export_id, on: :create

  validates :export_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validate :filters_are_an_object
  validate :completed_file_is_attached
  validate :valid_status_transition, on: :update

  def claim_for_processing!
    transitioned = self.class.where(id: id, status: "pending").update_all(
      status: "processing",
      updated_at: Time.current
    )
    reload
    transitioned == 1
  end

  def publish!(generated_file)
    return false unless processing?

    file.attach(
      io: generated_file,
      filename: "orders-#{export_id}.csv",
      content_type: "text/csv",
      identify: false
    )

    transitioned = self.class.where(id: id, status: "processing").update_all(
      status: "completed",
      updated_at: Time.current
    )
    reload

    return true if transitioned == 1

    file.purge unless completed?
    false
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

  def assign_export_id
    self.export_id ||= SecureRandom.uuid
  end

  def filters_are_an_object
    errors.add(:filters, "must be an object") unless filters.is_a?(Hash)
  end

  def completed_file_is_attached
    errors.add(:file, "must be attached for a completed export") if completed? && !file.attached?
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
