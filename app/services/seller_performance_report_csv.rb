class SellerPerformanceReportCsv
  HEADERS = %w[
    month
    orders
    items
    gross_value
    freight
    average_order_value
    late_orders
    late_percentage
  ].freeze

  MONTH_SQL = "DATE_TRUNC('month', orders.purchase_at)".freeze

  def initialize(report)
    @report = report
  end

  def generate
    CSV.generate do |csv|
      csv << HEADERS

      aggregate_rows.each do |row|
        order_count = row.order_count.to_i
        late_order_count = row.late_order_count.to_i
        gross_value = decimal(row.gross_value)

        csv << [
          row.month,
          order_count,
          row.item_count.to_i,
          decimal_string(gross_value),
          decimal_string(row.freight),
          decimal_string(gross_value / order_count),
          late_order_count,
          decimal_string(decimal(late_order_count) * 100 / order_count)
        ]
      end
    end
  end

  private

  def aggregate_rows
    OrderItem
      .joins(:order)
      .where(seller_id: @report.seller_id)
      .where("orders.purchase_at >= ?", @report.start_date.in_time_zone.beginning_of_day)
      .where("orders.purchase_at < ?", @report.end_date.next_day.in_time_zone.beginning_of_day)
      .select(
        "TO_CHAR(#{MONTH_SQL}, 'YYYY-MM') AS month",
        "COUNT(DISTINCT orders.id) AS order_count",
        "COUNT(order_items.id) AS item_count",
        "SUM(order_items.price) AS gross_value",
        "SUM(order_items.freight_value) AS freight",
        <<~SQL.squish
          COUNT(DISTINCT CASE
            WHEN orders.delivered_customer_at IS NOT NULL
              AND orders.delivered_customer_at > orders.estimated_delivery_at
            THEN orders.id
          END) AS late_order_count
        SQL
      )
      .group(Arel.sql(MONTH_SQL))
      .order(Arel.sql("#{MONTH_SQL} ASC"))
  end

  def decimal(value)
    BigDecimal(value.to_s)
  end

  def decimal_string(value)
    integer, fraction = decimal(value).round(2).to_s("F").split(".", 2)
    "#{integer}.#{fraction.to_s.ljust(2, "0")}"
  end
end
