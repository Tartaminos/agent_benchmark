module Api
  class OrdersController < ApplicationController
    DELIVERY_STATUS_SQL = <<~SQL.squish.freeze
      CASE
        WHEN delivered_customer_at IS NULL THEN 'pending'
        WHEN delivered_customer_at <= estimated_delivery_at THEN 'on_time'
        ELSE 'late'
      END
    SQL

    def delivery_index
      page = pagination_value(params[:page], 1)
      requested_per_page = pagination_value(params[:per_page], 25)

      unless page && requested_per_page
        render json: { error: "invalid_pagination" }, status: :unprocessable_content
        return
      end

      per_page = [requested_per_page, 100].min
      delivery_status = params[:delivery_status]

      unless delivery_status.nil? || (delivery_status.is_a?(String) && %w[pending on_time late].include?(delivery_status))
        render json: { error: "invalid_delivery_status" }, status: :unprocessable_content
        return
      end

      orders = Order.all
      orders = case delivery_status
      when "pending"
        orders.where(delivered_customer_at: nil)
      when "on_time"
        orders.where.not(delivered_customer_at: nil)
          .where("delivered_customer_at <= estimated_delivery_at")
      when "late"
        orders.where("delivered_customer_at > estimated_delivery_at")
      else
        orders
      end

      total_orders = orders.count
      orders = orders
        .select(
          :order_id,
          :status,
          :purchase_at,
          :estimated_delivery_at,
          :delivered_customer_at,
          "#{DELIVERY_STATUS_SQL} AS delivery_status"
        )
        .order(purchase_at: :desc, order_id: :asc)
        .limit(per_page)
        .offset((page - 1) * per_page)
        .to_a

      render json: {
        page: page,
        per_page: per_page,
        total_orders: total_orders,
        total_pages: total_orders.zero? ? 0 : (total_orders.to_f / per_page).ceil,
        orders: orders.map do |order|
          {
            order_id: order.order_id,
            status: order.status,
            purchase_at: timestamp(order.purchase_at),
            estimated_delivery_at: timestamp(order.estimated_delivery_at),
            delivered_customer_at: timestamp(order.delivered_customer_at),
            delivery_status: order.delivery_status
          }
        end
      }
    end

    def index
      page = pagination_value(params[:page], 1)
      per_page = pagination_value(params[:per_page], 20)

      unless page && per_page && per_page <= 100
        render json: { error: "invalid_pagination" }, status: :unprocessable_content
        return
      end

      seller = Seller.find_by(seller_id: params[:seller_id])

      unless seller
        render json: { error: "seller_not_found" }, status: :not_found
        return
      end

      seller_items = OrderItem.where(seller_id: seller.id)
      total_orders = seller_items.distinct.count(:order_id)
      orders = Order.joins(:order_items)
        .where(order_items: { seller_id: seller.id })
        .select(
          "orders.id",
          "orders.order_id",
          "orders.status",
          "orders.purchase_at", 
          "COUNT(order_items.id) AS seller_item_count",
          "COALESCE(SUM(order_items.price), 0) AS seller_items_value",
          "COALESCE(SUM(order_items.freight_value), 0) AS seller_freight_value"
        )
        .group("orders.id")
        .order(purchase_at: :desc, order_id: :asc)
        .limit(per_page)
        .offset((page - 1) * per_page)
        .to_a

      products_by_order = Hash.new { |hash, order_id| hash[order_id] = [] }
      if orders.any?
        OrderItem.joins(:product)
          .where(seller_id: seller.id, order_id: orders.map(&:id))
          .distinct
          .order(:order_id, "products.product_id")
          .pluck(:order_id, "products.product_id", "products.category_name")
          .each do |order_id, product_id, category_name|
            products_by_order[order_id] << { product_id: product_id, category_name: category_name }
          end
      end

      render json: {
        seller_id: seller.seller_id,
        page: page,
        per_page: per_page,
        total_orders: total_orders,
        orders: orders.map do |order|
          items_value = order.seller_items_value
          freight_value = order.seller_freight_value

          {
            order_id: order.order_id,
            status: order.status,
            purchase_at: timestamp(order.purchase_at),
            item_count: order.seller_item_count,
            items_value: money(items_value),
            freight_value: money(freight_value),
            total_value: money(items_value + freight_value),
            products: products_by_order[order.id]
          }
        end
      }
    end

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

    def pagination_value(value, default)
      return default if value.nil?
      return unless value.is_a?(String) && value.match?(/\A[0-9]+\z/)

      number = value.to_i
      number if number.positive?
    end

    def timestamp(value)
      value&.utc&.iso8601(3)
    end

    def money(value)
      whole, fraction = value.round(2).to_s("F").split(".", 2)
      "#{whole}.#{fraction.to_s.ljust(2, "0")[0, 2]}"
    end
  end
end
