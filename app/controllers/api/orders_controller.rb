module Api
  class OrdersController < ApplicationController
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
  end
end
