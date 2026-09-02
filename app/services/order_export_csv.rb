require "csv"

class OrderExportCsv
  BATCH_SIZE = 1_000
  HEADERS = %w[
    order_id
    customer_id
    customer_state
    order_status
    delivery_status
    purchase_at
    estimated_delivery_at
    delivered_customer_at
    items_total
    freight_total
    order_total
    paid_total
  ].freeze

  def initialize(export)
    @export = export
  end

  def generate
    CSV.generate do |csv|
      csv << HEADERS
      each_order_batch { |orders| append_rows(csv, orders) }
    end
  end

  private

  attr_reader :export

  def each_order_batch
    cursor = nil

    loop do
      orders = filtered_orders
      if cursor
        orders = orders.where(
          "orders.purchase_at > :purchase_at OR " \
            "(orders.purchase_at = :purchase_at AND orders.order_id > :order_id)",
          purchase_at: cursor.fetch(:purchase_at),
          order_id: cursor.fetch(:order_id)
        )
      end

      batch = orders.order(purchase_at: :asc, order_id: :asc).limit(BATCH_SIZE).to_a
      break if batch.empty?

      yield batch
      last = batch.last
      cursor = { purchase_at: last.purchase_at, order_id: last.order_id }
    end
  end

  def filtered_orders
    relation = Order
      .joins(:customer)
      .select(
        :id,
        :order_id,
        :status,
        :purchase_at,
        :estimated_delivery_at,
        :delivered_customer_at,
        "customers.customer_id AS external_customer_id",
        "customers.state AS customer_state"
      )
    relation = relation.where(status: export.order_status) if export.order_status
    relation = relation.with_delivery_status(export.delivery_status)
    relation = relation.where(customers: { state: export.customer_state }) if export.customer_state
    relation = relation.where("orders.purchase_at >= ?", utc_start(export.purchase_from)) if export.purchase_from
    if export.purchase_to
      relation = relation.where("orders.purchase_at < ?", utc_start(export.purchase_to.next_day))
    end
    relation
  end

  def append_rows(csv, orders)
    internal_ids = orders.map(&:id)
    item_totals = OrderItem
      .where(order_id: internal_ids)
      .group(:order_id)
      .pluck(
        :order_id,
        Arel.sql("COALESCE(SUM(price), 0)"),
        Arel.sql("COALESCE(SUM(freight_value), 0)")
      )
      .to_h { |order_id, items, freight| [ order_id, [ decimal(items), decimal(freight) ] ] }
    payment_totals = OrderPayment
      .where(order_id: internal_ids)
      .group(:order_id)
      .sum(:payment_value)

    orders.each do |order|
      items_total, freight_total = item_totals.fetch(order.id, [ BigDecimal("0"), BigDecimal("0") ])
      paid_total = decimal(payment_totals.fetch(order.id, 0))

      csv << [
        order.order_id,
        order.external_customer_id,
        order.customer_state,
        order.status,
        order.delivery_status,
        timestamp(order.purchase_at),
        timestamp(order.estimated_delivery_at),
        timestamp(order.delivered_customer_at),
        money(items_total),
        money(freight_total),
        money(items_total + freight_total),
        money(paid_total)
      ]
    end
  end

  def utc_start(date)
    Time.utc(date.year, date.month, date.day)
  end

  def decimal(value)
    BigDecimal(value.to_s)
  end

  def money(value)
    whole, fractional = decimal(value).round(2).to_s("F").split(".", 2)
    "#{whole}.#{fractional.to_s.ljust(2, "0")[0, 2]}"
  end

  def timestamp(value)
    value&.utc&.iso8601(3)
  end
end
