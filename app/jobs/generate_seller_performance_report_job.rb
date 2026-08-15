class GenerateSellerPerformanceReportJob < ApplicationJob
  def perform(report_public_id)
    report = SellerPerformanceReport.find_by(public_id: report_public_id)
    return unless report
    return unless claim(report)

    csv_data = SellerPerformanceReportCsv.new(report).generate
    complete(report, csv_data)
  rescue StandardError
    fail_report(report) if report
    raise
  end

  private

  def claim(report)
    SellerPerformanceReport
      .where(id: report.id, status: "pending")
      .update_all(status: "processing", updated_at: Time.current) == 1
  end

  def complete(report, csv_data)
    SellerPerformanceReport
      .where(id: report.id, status: "processing")
      .update_all(status: "completed", csv_data: csv_data, updated_at: Time.current)
  end

  def fail_report(report)
    SellerPerformanceReport
      .where(id: report.id, status: %w[pending processing])
      .update_all(status: "failed", csv_data: nil, updated_at: Time.current)
  end
end
