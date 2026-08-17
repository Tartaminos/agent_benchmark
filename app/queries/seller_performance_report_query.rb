class SellerPerformanceReportQuery
  MONTH_SQL = "DATE_TRUNC('month', orders.purchase_at)".freeze
  LATE_ORDERS_SQL = <<~SQL.squish.freeze
    COUNT(DISTINCT CASE
      WHEN orders.delivered_customer_at IS NOT NULL
        AND orders.delivered_customer_at > orders.estimated_delivery_at
      THEN orders.id
    END)
  SQL

  def initialize(seller:, start_date:, end_date:)
    @seller = seller
    @start_date = start_date
    @end_date = end_date
  end

  def rows
    OrderItem
      .joins(:order)
      .where(seller_id: seller.id)
      .where(orders: { purchase_at: start_time...end_time })
      .select(
        "#{MONTH_SQL} AS month",
        "COUNT(DISTINCT orders.id) AS orders",
        "COUNT(order_items.id) AS items",
        "SUM(order_items.price) AS gross_value",
        "SUM(order_items.freight_value) AS freight",
        "#{LATE_ORDERS_SQL} AS late_orders"
      )
      .group(Arel.sql(MONTH_SQL))
      .order(Arel.sql("#{MONTH_SQL} ASC"))
  end

  private

  attr_reader :seller, :start_date, :end_date

  def start_time
    Time.utc(start_date.year, start_date.month, start_date.day)
  end

  def end_time
    day_after_end = end_date.next_day
    Time.utc(day_after_end.year, day_after_end.month, day_after_end.day)
  end
end
