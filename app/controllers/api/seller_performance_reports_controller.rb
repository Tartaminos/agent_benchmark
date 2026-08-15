module Api
  class SellerPerformanceReportsController < ApplicationController
    CANONICAL_DATE = /\A\d{4}-\d{2}-\d{2}\z/

    skip_forgery_protection only: :create

    def create
      start_date = parse_date(params[:start_date])
      end_date = parse_date(params[:end_date])

      unless start_date && end_date && start_date <= end_date
        return render json: { error: "invalid_date_range" }, status: :unprocessable_content
      end

      seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless seller

      @report = SellerPerformanceReport.create!(
        seller: seller,
        start_date: start_date,
        end_date: end_date
      )

      enqueue_report
    end

    private

    def parse_date(value)
      return unless value.is_a?(String) && CANONICAL_DATE.match?(value)

      date = Date.iso8601(value)
      date if date.iso8601 == value
    rescue Date::Error
      nil
    end

    def enqueue_report
      enqueued_job = begin
        GenerateSellerPerformanceReportJob.perform_later(@report.public_id)
      rescue StandardError
        nil
      end

      return render status: :accepted if enqueued_job

      mark_enqueue_failed
    end

    def mark_enqueue_failed
      @report.update_columns(status: "failed", csv_data: nil, updated_at: Time.current)
      render json: { error: "report_enqueue_failed" }, status: :service_unavailable
    end
  end
end
