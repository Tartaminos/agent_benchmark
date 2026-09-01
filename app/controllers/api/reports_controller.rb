module Api
  class ReportsController < ApplicationController
    before_action :load_report

    def show
      payload = {
        report_id: @report.report_id,
        seller_id: @report.seller.seller_id,
        status: @report.status,
        start_date: @report.start_date.iso8601,
        end_date: @report.end_date.iso8601
      }
      payload[:download_url] = download_api_report_path(report_id: @report.report_id) if @report.completed?

      render json: payload
    end

    def download
      return render json: { error: "report_not_ready" }, status: :conflict unless @report.completed?

      send_data @report.csv_data,
                type: "text/csv; charset=utf-8",
                disposition: "attachment",
                filename: "seller-performance-#{@report.report_id}.csv"
    end

    private

    def load_report
      @report = SellerPerformanceReport.includes(:seller).find_by(report_id: params[:report_id])
      render json: { error: "report_not_found" }, status: :not_found unless @report
    end
  end
end
