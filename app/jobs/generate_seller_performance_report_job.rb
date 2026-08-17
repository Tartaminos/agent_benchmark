class GenerateSellerPerformanceReportJob < ApplicationJob
  CSV_HEADERS = %w[
    month orders items gross_value freight average_order_value late_orders late_percentage
  ].freeze

  def perform(report_id)
    claimed = SellerPerformanceReport
      .where(id: report_id, status: "pending")
      .update_all(status: "processing", updated_at: Time.current)
    return unless claimed == 1

    report = SellerPerformanceReport.find(report_id)
    csv_content = generate_csv(report)

    SellerPerformanceReport
      .where(id: report_id, status: "processing")
      .update_all(status: "completed", csv_content: csv_content, updated_at: Time.current)
  rescue StandardError
    SellerPerformanceReport
      .where(id: report_id, status: %w[pending processing])
      .update_all(status: "failed", csv_content: nil, updated_at: Time.current)
  end

  private

  def generate_csv(report)
    rows = SellerPerformanceReportQuery.new(
      seller: report.seller,
      start_date: report.start_date,
      end_date: report.end_date
    ).rows

    CSV.generate do |csv|
      csv << CSV_HEADERS
      rows.each { |row| csv << csv_row(row) }
    end
  end

  def csv_row(row)
    orders = row.orders.to_i
    late_orders = row.late_orders.to_i
    gross_value = BigDecimal(row.gross_value.to_s)

    [
      row.month.strftime("%Y-%m"),
      orders,
      row.items.to_i,
      decimal(gross_value),
      decimal(BigDecimal(row.freight.to_s)),
      decimal(orders.zero? ? 0 : gross_value / orders),
      late_orders,
      decimal(orders.zero? ? 0 : BigDecimal(late_orders.to_s) * 100 / orders)
    ]
  end

  def decimal(value)
    whole, fraction = BigDecimal(value.to_s).round(2).to_s("F").split(".", 2)
    "#{whole}.#{fraction.to_s.ljust(2, "0")[0, 2]}"
  end
end
