class GenerateSellerPerformanceReportJob < ApplicationJob
  queue_as :default

  def perform(report_id)
    report = SellerPerformanceReport.find_by(report_id: report_id)
    return unless report&.begin_processing!

    csv_data = SellerPerformanceReportGenerator.new(report).call
    report.complete!(csv_data)
  rescue StandardError
    report&.fail!
  end
end
