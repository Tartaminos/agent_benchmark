require "csv"

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

  def initialize(report)
    @report = report
  end

  def generate
    CSV.generate do |csv|
      csv << HEADERS

      monthly_rows.each do |row|
        orders = row["orders"].to_i
        late_orders = row["late_orders"].to_i
        gross_value = decimal(row["gross_value"])

        csv << [
          row["month"],
          orders,
          row["items"].to_i,
          decimal_string(gross_value),
          decimal_string(decimal(row["freight"])),
          decimal_string(orders.zero? ? 0 : gross_value / orders),
          late_orders,
          decimal_string(orders.zero? ? 0 : decimal(late_orders) * 100 / orders)
        ]
      end
    end
  end

  private

  attr_reader :report

  def monthly_rows
    sql = ApplicationRecord.sanitize_sql_array([
      <<~SQL.squish,
        SELECT
          TO_CHAR(DATE_TRUNC('month', orders.purchase_at), 'YYYY-MM') AS month,
          COUNT(DISTINCT orders.id) AS orders,
          COUNT(order_items.id) AS items,
          SUM(order_items.price) AS gross_value,
          SUM(order_items.freight_value) AS freight,
          COUNT(DISTINCT CASE
            WHEN orders.delivered_customer_at IS NOT NULL
              AND orders.delivered_customer_at > orders.estimated_delivery_at
            THEN orders.id
          END) AS late_orders
        FROM order_items
        INNER JOIN orders ON orders.id = order_items.order_id
        WHERE order_items.seller_id = ?
          AND orders.purchase_at >= ?
          AND orders.purchase_at < ?
        GROUP BY DATE_TRUNC('month', orders.purchase_at)
        ORDER BY DATE_TRUNC('month', orders.purchase_at) ASC
      SQL
      report.seller_id,
      utc_start(report.start_date),
      utc_start(report.end_date.next_day)
    ])

    ApplicationRecord.connection.select_all(sql)
  end

  def utc_start(date)
    Time.utc(date.year, date.month, date.day)
  end

  def decimal(value)
    BigDecimal(value.to_s)
  end

  def decimal_string(value)
    whole, fractional = decimal(value).round(2).to_s("F").split(".", 2)

    "#{whole}.#{fractional.to_s.ljust(2, "0")[0, 2]}"
  end
end
