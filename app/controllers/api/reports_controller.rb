module Api
  class ReportsController < ActionController::API
    def show
      report = find_report
      return report_not_found unless report

      response = {
        report_id: report.report_id,
        seller_id: report.seller.seller_id,
        status: report.status
      }
      response[:download_url] = api_report_download_path(report_id: report.report_id) if report.status == "completed"

      render json: response
    end

    def download
      report = find_report
      return report_not_found unless report
      unless report.status == "completed"
        return render json: { error: "report_not_ready" }, status: :conflict
      end

      send_data report.csv_content,
                type: "text/csv",
                disposition: "attachment",
                filename: "seller-performance-#{report.report_id}.csv"
    end

    private

    def find_report
      SellerPerformanceReport.includes(:seller).find_by(report_id: params[:report_id])
    end

    def report_not_found
      render json: { error: "report_not_found" }, status: :not_found
    end
  end
end
