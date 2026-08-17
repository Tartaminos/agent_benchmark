module Api
  class OrdersController < ApplicationController
    MAX_PER_PAGE = 100
    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 25
    DELIVERY_STATUSES = %w[pending on_time late].freeze

    DELIVERY_STATUS_SQL = <<~SQL.squish.freeze
      CASE
        WHEN orders.delivered_customer_at IS NULL THEN 'pending'
        WHEN orders.delivered_customer_at <= orders.estimated_delivery_at THEN 'on_time'
        ELSE 'late'
      END
    SQL
    ON_TIME_PREDICATE = <<~SQL.squish.freeze
      orders.delivered_customer_at IS NOT NULL
        AND orders.delivered_customer_at <= orders.estimated_delivery_at
    SQL
    LATE_PREDICATE = <<~SQL.squish.freeze
      orders.delivered_customer_at IS NOT NULL
        AND orders.delivered_customer_at > orders.estimated_delivery_at
    SQL

    def index
      delivery_status = params[:delivery_status]
      unless valid_delivery_status?(delivery_status)
        return render json: { error: "invalid_delivery_status" }, status: :unprocessable_content
      end

      pagination = pagination_params
      return render json: { error: "invalid_pagination" }, status: :unprocessable_content unless pagination

      @page, @per_page = pagination
      filtered_orders = orders_for(delivery_status)
      @total_orders = filtered_orders.count
      @total_pages = (@total_orders + @per_page - 1) / @per_page
      offset = (@page - 1) * @per_page
      @orders = if offset >= @total_orders
        []
      else
        filtered_orders
          .select(
            "orders.order_id",
            "orders.status",
            "orders.purchase_at",
            "orders.estimated_delivery_at",
            "orders.delivered_customer_at",
            "#{DELIVERY_STATUS_SQL} AS delivery_status"
          )
          .order(purchase_at: :desc, order_id: :asc)
          .offset(offset)
          .limit(@per_page)
      end
    end

    def show
      @order = Order.includes(
        :customer,
        :order_payments,
        :order_reviews,
        order_items: %i[product seller]
      ).find_by(order_id: params[:order_id])

      render json: { error: "order_not_found" }, status: :not_found unless @order
    end

    private

    def valid_delivery_status?(delivery_status)
      delivery_status.nil? || DELIVERY_STATUSES.include?(delivery_status)
    end

    def pagination_params
      page = positive_integer_param(:page, DEFAULT_PAGE)
      per_page = positive_integer_param(:per_page, DEFAULT_PER_PAGE)

      return unless page && per_page && per_page <= MAX_PER_PAGE

      [ page, per_page ]
    end

    def positive_integer_param(name, default)
      value = params[name]
      return default if value.nil?
      return unless value.is_a?(String) && value.match?(/\A[1-9]\d*\z/)

      value.to_i
    end

    def orders_for(delivery_status)
      case delivery_status
      when "pending"
        Order.where(delivered_customer_at: nil)
      when "on_time"
        Order.where(ON_TIME_PREDICATE)
      when "late"
        Order.where(LATE_PREDICATE)
      else
        Order.all
      end
    end
  end
end
