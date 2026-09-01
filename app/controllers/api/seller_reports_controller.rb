module Api
  class SellerReportsController < ApplicationController
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/

    protect_from_forgery with: :null_session

    def create
      seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless seller

      dates = parsed_dates
      return render_invalid_parameters unless dates && dates[:start_date] <= dates[:end_date]

      report = seller.seller_performance_reports.create!(dates)
      return render_enqueue_failure(report) unless enqueue(report)

      render json: report_payload(report), status: :accepted
    end

    private

    def parsed_dates
      permitted = params.permit(:start_date, :end_date)
      start_date = parse_date(permitted[:start_date])
      end_date = parse_date(permitted[:end_date])
      return unless start_date && end_date

      { start_date: start_date, end_date: end_date }
    end

    def parse_date(value)
      return unless value.is_a?(String) && ISO_DATE.match?(value)

      Date.iso8601(value)
    rescue Date::Error
      nil
    end

    def report_payload(report)
      {
        report_id: report.report_id,
        seller_id: report.seller.seller_id,
        status: report.status
      }
    end

    def enqueue(report)
      GenerateSellerPerformanceReportJob.perform_later(report.report_id)
      true
    rescue StandardError
      false
    end

    def render_enqueue_failure(report)
      report.fail!
      render json: { error: "report_enqueue_failed", report_id: report.report_id }, status: :service_unavailable
    end

    def render_invalid_parameters
      render json: { error: "invalid_report_parameters" }, status: :unprocessable_entity
    end
  end
end
