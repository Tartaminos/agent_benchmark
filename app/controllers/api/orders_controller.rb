module Api
  class OrdersController < ActionController::API
    def show
      order = Order.find_by(order_id: params[:order_id])
      return render json: { error: "order_not_found" }, status: :not_found unless order

      preload_associations(order)

      items = order.order_items.sort_by(&:order_item_id)
      payments = order.order_payments.sort_by(&:payment_sequential)

      render json: order_json(order, items, payments)
    end

    private

    def preload_associations(order)
      ActiveRecord::Associations::Preloader.new(
        records: [ order ],
        associations: [
          :customer,
          { order_items: [ :product, :seller ] },
          :order_payments,
          :order_reviews
        ]
      ).call
    end

    def order_json(order, items, payments)
      items_total = items.sum(BigDecimal("0"), &:price)
      freight_total = items.sum(BigDecimal("0"), &:freight_value)
      paid_total = payments.sum(BigDecimal("0"), &:payment_value)

      {
        order_id: order.order_id,
        status: order.status,
        purchase_at: timestamp(order.purchase_at),
        approved_at: timestamp(order.approved_at),
        delivered_carrier_at: timestamp(order.delivered_carrier_at),
        delivered_customer_at: timestamp(order.delivered_customer_at),
        estimated_delivery_at: timestamp(order.estimated_delivery_at),
        customer: customer_json(order.customer),
        items: items.map { |item| item_json(item) },
        payments: payments.map { |payment| payment_json(payment) },
        reviews: order.order_reviews.map { |review| review_json(review) },
        totals: {
          items: money(items_total),
          freight: money(freight_total),
          order: money(items_total + freight_total),
          paid: money(paid_total)
        }
      }
    end

    def customer_json(customer)
      {
        customer_id: customer.customer_id,
        customer_unique_id: customer.customer_unique_id,
        city: customer.city,
        state: customer.state
      }
    end

    def item_json(item)
      {
        order_item_id: item.order_item_id,
        product_id: item.product.product_id,
        seller_id: item.seller.seller_id,
        price: money(item.price),
        freight_value: money(item.freight_value)
      }
    end

    def payment_json(payment)
      {
        payment_sequential: payment.payment_sequential,
        payment_type: payment.payment_type,
        payment_installments: payment.payment_installments,
        payment_value: money(payment.payment_value)
      }
    end

    def review_json(review)
      {
        review_id: review.review_id,
        score: review.score,
        comment_title: review.comment_title,
        comment_message: review.comment_message,
        creation_at: timestamp(review.creation_at),
        answer_at: timestamp(review.answer_at)
      }
    end

    def money(value)
      whole, fractional = value.round(2).to_s("F").split(".", 2)

      "#{whole}.#{fractional.to_s.ljust(2, "0")[0, 2]}"
    end

    def timestamp(value)
      value&.utc&.iso8601(3)
    end
  end
end
