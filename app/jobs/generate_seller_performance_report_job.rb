class GenerateSellerPerformanceReportJob < ApplicationJob
  def perform(report_id)
    report = SellerPerformanceReport.find_by(report_id: report_id)
    return unless report

    claimed = SellerPerformanceReport
      .where(id: report.id, status: "pending")
      .update_all(status: "processing", updated_at: Time.current)
    return unless claimed == 1

    csv_content = SellerPerformanceReportCsv.new(report.reload).generate

    SellerPerformanceReport
      .where(id: report.id, status: "processing")
      .update_all(csv_content: csv_content, status: "completed", updated_at: Time.current)
  rescue StandardError => error
    SellerPerformanceReport
      .where(report_id: report_id, status: %w[pending processing])
      .update_all(csv_content: nil, status: "failed", updated_at: Time.current)
    Rails.logger.error(
      "Seller performance report generation failed " \
        "report_id=#{report_id} error=#{error.class}: #{error.message}"
    )
    raise
  end
end
