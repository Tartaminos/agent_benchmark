module Api
  class SellerReportsController < ApplicationController
    skip_forgery_protection only: :create

    def create
      seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless seller

      dates = report_dates
      return render json: { error: "invalid_date_range" }, status: :unprocessable_content unless dates

      report = SellerPerformanceReport.create!(
        seller: seller,
        start_date: dates.first,
        end_date: dates.last
      )

      begin
        GenerateSellerPerformanceReportJob.perform_later(report.id)
      rescue StandardError
        report.update_columns(status: "failed", csv_content: nil, updated_at: Time.current)
        return render json: { error: "report_enqueue_failed" }, status: :internal_server_error
      end

      render json: {
        report_id: report.public_id,
        seller_id: seller.seller_id,
        status: report.status
      }, status: :accepted
    end

    private

    def report_dates
      start_date = strict_date(params[:start_date])
      end_date = strict_date(params[:end_date])
      return unless start_date && end_date && start_date <= end_date

      [ start_date, end_date ]
    end

    def strict_date(value)
      return unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(value)
    rescue Date::Error
      nil
    end
  end
end
