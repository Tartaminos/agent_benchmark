require "csv"

class SellerPerformanceReportGenerator
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

  QUERY = <<~SQL.squish.freeze
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

  def initialize(report)
    @report = report
  end

  def call
    CSV.generate(headers: HEADERS, write_headers: true) do |csv|
      result_rows.each do |row|
        orders = row.fetch("orders").to_i
        gross_value = BigDecimal(row.fetch("gross_value").to_s)
        late_orders = row.fetch("late_orders").to_i

        csv << [
          row.fetch("month"),
          orders,
          row.fetch("items").to_i,
          decimal(gross_value),
          decimal(row.fetch("freight")),
          decimal(orders.zero? ? 0 : gross_value / orders),
          late_orders,
          decimal(orders.zero? ? 0 : (BigDecimal(late_orders.to_s) / orders) * 100)
        ]
      end
    end
  end

  private

  attr_reader :report

  def result_rows
    sql = ApplicationRecord.sanitize_sql_array([
      QUERY,
      report.seller_id,
      report.start_date,
      report.end_date.next_day
    ])
    ApplicationRecord.connection.select_all(sql)
  end

  def decimal(value)
    format("%.2f", BigDecimal(value.to_s))
  end
end
