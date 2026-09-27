module Api
  class OrdersController < ApplicationController
    def show
      order = Order.find_by(order_id: params[:order_id])

      unless order
        render json: { error: "order_not_found" }, status: :not_found
        return
      end

      items = order.order_items.order(:order_item_id)
      payments = order.order_payments.order(:payment_sequential)
      reviews = order.order_reviews.order(:id)
      item_total = items.sum(:price)
      freight_total = items.sum(:freight_value)
      paid_total = payments.sum(:payment_value)

      render json: {
        order_id: order.order_id,
        status: order.status,
        purchase_at: timestamp(order.purchase_at),
        approved_at: timestamp(order.approved_at),
        delivered_carrier_at: timestamp(order.delivered_carrier_at),
        delivered_customer_at: timestamp(order.delivered_customer_at),
        estimated_delivery_at: timestamp(order.estimated_delivery_at),
        customer: {
          customer_id: order.customer.customer_id,
          customer_unique_id: order.customer.customer_unique_id,
          city: order.customer.city,
          state: order.customer.state
        },
        items: items.map do |item|
          {
            order_item_id: item.order_item_id,
            product_id: item.product.product_id,
            seller_id: item.seller.seller_id,
            price: money(item.price),
            freight_value: money(item.freight_value)
          }
        end,
        payments: payments.map do |payment|
          {
            payment_sequential: payment.payment_sequential,
            payment_type: payment.payment_type,
            payment_installments: payment.payment_installments,
            payment_value: money(payment.payment_value)
          }
        end,
        reviews: reviews.map do |review|
          {
            review_id: review.review_id,
            score: review.score,
            comment_title: review.comment_title,
            comment_message: review.comment_message,
            creation_at: timestamp(review.creation_at),
            answer_at: timestamp(review.answer_at)
          }
        end,
        totals: {
          items: money(item_total),
          freight: money(freight_total),
          order: money(item_total + freight_total),
          paid: money(paid_total)
        }
      }
    end

    private

    def timestamp(value)
      value&.utc&.iso8601(3)
    end

    def money(value)
      whole, fraction = value.round(2).to_s("F").split(".", 2)
      "#{whole}.#{fraction.to_s.ljust(2, "0")[0, 2]}"
    end
  end
end
