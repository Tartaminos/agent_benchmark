module Api
  class ReportsController < ApplicationController
    before_action :find_report

    def show
    end

    def download
      unless @report.completed?
        return render json: { error: "report_not_ready" }, status: :conflict
      end

      send_data(
        @report.csv_data,
        type: "text/csv",
        disposition: "attachment",
        filename: "seller-performance-report-#{@report.public_id}.csv"
      )
    end

    private

    def find_report
      @report = SellerPerformanceReport.find_by(public_id: params[:report_id])
      return if @report

      render json: { error: "report_not_found" }, status: :not_found
    end
  end
end
