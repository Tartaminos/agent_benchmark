require "csv"
require "tempfile"

class OrderExportGenerator
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

  def initialize(order_export)
    @order_export = order_export
  end

  def call
    tempfile = Tempfile.new([ "order-export-", ".csv" ], binmode: true)
    csv = CSV.new(tempfile)
    csv << HEADERS

    each_batch do |orders|
      totals_by_order = item_totals(orders)
      payments_by_order = payment_totals(orders)

      orders.each do |order|
        internal_id, order_id, customer_id, state, status, purchase_at,
          estimated_delivery_at, delivered_customer_at = order
        items_total, freight_total = totals_by_order.fetch(internal_id, ZERO_TOTALS)

        csv << [
          order_id,
          customer_id,
          state,
          status,
          delivery_status(delivered_customer_at, estimated_delivery_at),
          timestamp(purchase_at),
          timestamp(estimated_delivery_at),
          timestamp(delivered_customer_at),
          decimal(items_total),
          decimal(freight_total),
          decimal(items_total + freight_total),
          decimal(payments_by_order.fetch(internal_id, BigDecimal("0")))
        ]
      end
    end

    tempfile.rewind
    tempfile
  rescue StandardError
    tempfile&.close!
    raise
  end

  private

  ZERO_TOTALS = [ BigDecimal("0"), BigDecimal("0") ].freeze

  attr_reader :order_export

  def each_batch
    relation = filtered_orders
    cursor = nil

    loop do
      batch = relation
      if cursor
        batch = batch.where(
          "orders.purchase_at > :purchase_at OR " \
            "(orders.purchase_at = :purchase_at AND orders.order_id > :order_id)",
          purchase_at: cursor.fetch(:purchase_at),
          order_id: cursor.fetch(:order_id)
        )
      end

      rows = batch
        .order("orders.purchase_at ASC", "orders.order_id ASC")
        .limit(BATCH_SIZE)
        .pluck(
          "orders.id",
          "orders.order_id",
          "customers.customer_id",
          "customers.state",
          "orders.status",
          "orders.purchase_at",
          "orders.estimated_delivery_at",
          "orders.delivered_customer_at"
        )
      break if rows.empty?

      yield rows
      cursor = { purchase_at: rows.last.fetch(5), order_id: rows.last.fetch(1) }
    end
  end

  def filtered_orders
    filters = order_export.filters
    relation = Order.joins(:customer)
    relation = relation.where(status: filters.fetch("order_status")) if filters.key?("order_status")
    relation = relation.for_delivery_status(filters.fetch("delivery_status")) if filters.key?("delivery_status")
    relation = relation.where(customers: { state: filters.fetch("customer_state") }) if filters.key?("customer_state")
    if filters.key?("purchase_from")
      relation = relation.where("orders.purchase_at >= ?", Date.iso8601(filters.fetch("purchase_from")).beginning_of_day)
    end
    if filters.key?("purchase_to")
      relation = relation.where("orders.purchase_at < ?", Date.iso8601(filters.fetch("purchase_to")).next_day.beginning_of_day)
    end
    relation
  end

  def item_totals(orders)
    ids = orders.map(&:first)
    OrderItem
      .where(order_id: ids)
      .group(:order_id)
      .pluck(:order_id, Arel.sql("SUM(price)"), Arel.sql("SUM(freight_value)"))
      .to_h { |order_id, items, freight| [ order_id, [ BigDecimal(items.to_s), BigDecimal(freight.to_s) ] ] }
  end

  def payment_totals(orders)
    ids = orders.map(&:first)
    OrderPayment
      .where(order_id: ids)
      .group(:order_id)
      .sum(:payment_value)
  end

  def delivery_status(delivered_at, estimated_at)
    return "pending" unless delivered_at

    delivered_at <= estimated_at ? "on_time" : "late"
  end

  def timestamp(value)
    value&.utc&.iso8601(3)
  end

  def decimal(value)
    format("%.2f", BigDecimal(value.to_s))
  end
end
