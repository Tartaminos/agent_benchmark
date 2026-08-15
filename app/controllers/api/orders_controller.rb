module Api
  class OrdersController < ApplicationController
    def show
      @order = Order.includes(
        :customer,
        :order_payments,
        :order_reviews,
        order_items: %i[product seller]
      ).find_by(order_id: params[:order_id])

      render json: { error: "order_not_found" }, status: :not_found unless @order
    end
  end
end
