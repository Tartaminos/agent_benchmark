module Api
  class OrdersController < ApplicationController
    MAX_PER_PAGE = 100
    MAX_DATABASE_OFFSET = (2**63) - 1
    POSITIVE_INTEGER = /\A[1-9][0-9]*\z/

    def index
      return render_invalid_delivery_status unless valid_delivery_status?
      return render_invalid_pagination unless valid_pagination?

      @page = pagination_value(:page, 1)
      @per_page = pagination_value(:per_page, 25)

      orders = Order.all
      orders = orders.for_delivery_status(params[:delivery_status]) if params.key?(:delivery_status)

      @total_orders = orders.count
      @total_pages = (@total_orders + @per_page - 1) / @per_page
      @orders = load_orders(orders)
    end

    def show
      @order = Order.preload(
        :customer,
        { order_items: %i[product seller] },
        :order_payments,
        :order_reviews
      ).find_by!(order_id: params[:order_id])

      @items = @order.order_items.sort_by(&:order_item_id)
      @payments = @order.order_payments.sort_by(&:payment_sequential)
      @reviews = @order.order_reviews

      items_total = @items.sum(BigDecimal("0"), &:price)
      freight_total = @items.sum(BigDecimal("0"), &:freight_value)

      @totals = {
        items: items_total,
        freight: freight_total,
        order: items_total + freight_total,
        paid: @payments.sum(BigDecimal("0"), &:payment_value)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "order_not_found" }, status: :not_found
    end

    private

    def valid_delivery_status?
      !params.key?(:delivery_status) || Order::DELIVERY_STATUSES.include?(params[:delivery_status])
    end

    def valid_pagination?
      valid_parameter?(:page) &&
        valid_parameter?(:per_page) &&
        (!params.key?(:per_page) || params[:per_page].to_i <= MAX_PER_PAGE)
    end

    def valid_parameter?(name)
      return true unless params.key?(name)

      value = params[name]
      value.is_a?(String) && POSITIVE_INTEGER.match?(value)
    end

    def pagination_value(name, default)
      params.key?(name) ? params[name].to_i : default
    end

    def load_orders(orders)
      offset = (@page - 1) * @per_page
      return Order.none.to_a if offset > MAX_DATABASE_OFFSET

      orders
        .with_delivery_status
        .order(purchase_at: :desc, order_id: :asc)
        .limit(@per_page)
        .offset(offset)
        .to_a
    end

    def render_invalid_delivery_status
      render json: { error: "invalid_delivery_status" }, status: :unprocessable_entity
    end

    def render_invalid_pagination
      render json: { error: "invalid_pagination" }, status: :unprocessable_entity
    end
  end
end
