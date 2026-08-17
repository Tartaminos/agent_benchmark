module Admin
  class OrdersQuery
    DELIVERY_STATUS_SQL = <<~SQL.squish.freeze
      CASE
        WHEN orders.delivered_customer_at IS NULL THEN 'pending'
        WHEN orders.delivered_customer_at <= orders.estimated_delivery_at THEN 'on_time'
        ELSE 'late'
      END
    SQL

    attr_reader :filters

    def initialize(filters)
      @filters = filters
    end

    def relation
      scope = Order.joins(:customer)
      scope = scope.where(order_id: filters[:order_id]) if filters[:order_id].present?
      scope = scope.where(status: filters[:status]) if filters[:status].present?
      scope = scope.where(customers: { state: filters[:customer_state] }) if filters[:customer_state].present?
      scope = apply_delivery_status(scope)
      scope = scope.where("orders.purchase_at >= ?", filters[:purchase_from].beginning_of_day) if filters[:purchase_from]
      scope = scope.where("orders.purchase_at < ?", filters[:purchase_to].next_day.beginning_of_day) if filters[:purchase_to]
      scope
    end

    def page(page:, per_page:, direction:)
      relation
        .select(
          "orders.*",
          "customers.state AS customer_state",
          "#{DELIVERY_STATUS_SQL} AS delivery_status"
        )
        .order(purchase_at: direction.to_sym, order_id: :asc)
        .limit(per_page)
        .offset((page - 1) * per_page)
    end

    private

    def apply_delivery_status(scope)
      case filters[:delivery_status]
      when "pending"
        scope.where(delivered_customer_at: nil)
      when "on_time"
        scope.where("orders.delivered_customer_at IS NOT NULL AND orders.delivered_customer_at <= orders.estimated_delivery_at")
      when "late"
        scope.where("orders.delivered_customer_at IS NOT NULL AND orders.delivered_customer_at > orders.estimated_delivery_at")
      else
        scope
      end
    end
  end
end
