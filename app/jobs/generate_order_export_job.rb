class GenerateOrderExportJob < ApplicationJob
  def perform(export_id)
    export = OrderExport.find_by(export_id: export_id)
    return unless export

    claimed = OrderExport
      .where(id: export.id, status: "pending")
      .update_all(status: "processing", updated_at: Time.current)
    return unless claimed == 1

    csv_content = OrderExportCsv.new(export.reload).generate

    OrderExport
      .where(id: export.id, status: "processing")
      .update_all(csv_content: csv_content, status: "completed", updated_at: Time.current)
  rescue StandardError => error
    OrderExport
      .where(export_id: export_id, status: %w[pending processing])
      .update_all(csv_content: nil, status: "failed", updated_at: Time.current)
    Rails.logger.error(
      "Order export generation failed export_id=#{export_id} " \
        "error=#{error.class}: #{error.message}"
    )
    raise
  end
end
