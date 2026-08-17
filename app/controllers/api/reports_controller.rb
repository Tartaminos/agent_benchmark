module Api
  class ReportsController < ApplicationController
    before_action :find_report

    def show
      response = {
        report_id: @report.public_id,
        seller_id: @report.seller.seller_id,
        status: @report.status,
        start_date: @report.start_date.iso8601,
        end_date: @report.end_date.iso8601
      }
      if @report.completed?
        response[:download_url] = download_api_report_path(report_id: @report.public_id)
      end

      render json: response
    end

    def download
      unless @report.completed?
        return render json: { error: "report_not_ready" }, status: :conflict
      end

      send_data @report.csv_content,
                type: "text/csv",
                disposition: "attachment",
                filename: "seller-performance-#{@report.public_id}.csv"
    end

    private

    def find_report
      @report = SellerPerformanceReport.includes(:seller).find_by(public_id: params[:report_id])
      return if @report

      render json: { error: "report_not_found" }, status: :not_found
    end
  end
end
