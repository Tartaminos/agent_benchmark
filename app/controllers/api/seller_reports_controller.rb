module Api
  class SellerReportsController < ActionController::API
    def create
      dates = parsed_dates
      return render json: { error: "invalid_dates" }, status: :unprocessable_content unless dates

      seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless seller

      report = seller.seller_performance_reports.create!(
        start_date: dates.fetch(:start_date),
        end_date: dates.fetch(:end_date)
      )

      enqueue(report)
    end

    private

    def parsed_dates
      start_date = strict_date(params[:start_date])
      end_date = strict_date(params[:end_date])
      return unless start_date && end_date && start_date <= end_date

      { start_date: start_date, end_date: end_date }
    end

    def strict_date(value)
      return unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(value)
    rescue Date::Error
      nil
    end

    def enqueue(report)
      GenerateSellerPerformanceReportJob.perform_later(report.report_id)

      render json: report_json(report), status: :accepted
    rescue StandardError => error
      report.update_columns(csv_content: nil, status: "failed", updated_at: Time.current)
      Rails.logger.error(
        "Seller performance report enqueue failed " \
          "report_id=#{report.report_id} error=#{error.class}: #{error.message}"
      )
      render json: { error: "report_enqueue_failed" }, status: :service_unavailable
    end

    def report_json(report)
      {
        report_id: report.report_id,
        seller_id: report.seller.seller_id,
        status: report.status
      }
    end
  end
end
