json.report_id @report.public_id
json.seller_id @report.seller.seller_id
json.status @report.status
json.download_url download_api_report_url(@report.public_id) if @report.completed?
