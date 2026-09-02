class GenerateOrderExportJob < ApplicationJob
  queue_as :default

  def perform(export_id)
    order_export = OrderExport.find_by(export_id: export_id)
    return unless order_export&.claim_for_processing!

    generated_file = OrderExportGenerator.new(order_export).call
    order_export.publish!(generated_file)
  rescue StandardError => error
    Rails.logger.error("Order export #{export_id} failed (#{error.class}): #{error.message}")
    transitioned_to_failed = order_export&.fail!
    order_export.file.purge if transitioned_to_failed && order_export.file.attached?
  ensure
    generated_file&.close!
  end
end
