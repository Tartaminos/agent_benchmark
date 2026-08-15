module Api
  class OrdersController < ApplicationController
    POSITIVE_INTEGER = /\A[1-9]\d*\z/
    MAX_PER_PAGE = 100

    def index
      delivery_status = params[:delivery_status]
      unless delivery_status.nil? || Order::DELIVERY_STATUSES.include?(delivery_status)
        return render json: { error: "invalid_delivery_status" }, status: :unprocessable_content
      end

      @page = pagination_value(params[:page], default: 1)
      @per_page = pagination_value(params[:per_page], default: 25)

      unless @page && @per_page && @per_page <= MAX_PER_PAGE
        return render json: { error: "invalid_pagination" }, status: :unprocessable_content
      end

      orders = Order.with_delivery_status(delivery_status)
      @total_orders = orders.count
      @total_pages = (@total_orders + @per_page - 1) / @per_page
      offset = (@page - 1) * @per_page

      if offset >= @total_orders
        @orders = []
        return
      end

      @orders = orders
        .order(purchase_at: :desc, order_id: :asc)
        .offset(offset)
        .limit(@per_page)
    end

    def show
      @order = Order
        .includes(:customer, :order_payments, :order_reviews, order_items: %i[product seller])
        .find_by(order_id: params[:order_id])

      return render json: { error: "order_not_found" }, status: :not_found unless @order

      @items = @order.order_items.sort_by(&:order_item_id)
      @payments = @order.order_payments.sort_by(&:payment_sequential)
      @reviews = @order.order_reviews.to_a

      @items_total = @items.sum(BigDecimal("0"), &:price)
      @freight_total = @items.sum(BigDecimal("0"), &:freight_value)
      @order_total = @items_total + @freight_total
      @paid_total = @payments.sum(BigDecimal("0"), &:payment_value)
    end

    private

    def pagination_value(value, default:)
      return default if value.nil?
      return unless value.is_a?(String) && POSITIVE_INTEGER.match?(value)

      value.to_i
    end
  end
end
