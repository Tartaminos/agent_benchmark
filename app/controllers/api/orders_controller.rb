module Api
  class OrdersController < ApplicationController
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
  end
end
