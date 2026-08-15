module Api
  class SellerOrdersController < ApplicationController
    POSITIVE_INTEGER = /\A[1-9]\d*\z/
    MAX_PER_PAGE = 100

    def index
      @page = pagination_value(params[:page], default: 1)
      @per_page = pagination_value(params[:per_page], default: 20)

      unless @page && @per_page && @per_page <= MAX_PER_PAGE
        return render json: { error: "invalid_pagination" }, status: :unprocessable_content
      end

      @seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless @seller

      seller_items = OrderItem.where(seller_id: @seller.id)
      @total_orders = seller_items.distinct.count("order_items.order_id")
      offset = (@page - 1) * @per_page

      if offset >= @total_orders
        @orders = []
        @products_by_order_id = {}
        return
      end

      @orders = Order
        .joins(:order_items)
        .where(order_items: { seller_id: @seller.id })
        .select(
          "orders.id AS internal_order_id",
          "orders.order_id",
          "orders.status",
          "orders.purchase_at",
          "COUNT(order_items.id) AS item_count",
          "SUM(order_items.price) AS items_value",
          "SUM(order_items.freight_value) AS freight_value"
        )
        .group("orders.id")
        .order("orders.purchase_at DESC", "orders.order_id ASC")
        .offset(offset)
        .limit(@per_page)
        .to_a

      internal_order_ids = @orders.map(&:internal_order_id)
      @products_by_order_id = seller_items
        .joins(:product)
        .where(order_items: { order_id: internal_order_ids })
        .select(
          "order_items.order_id AS internal_order_id",
          "products.product_id AS external_product_id",
          "products.category_name"
        )
        .distinct
        .order("internal_order_id ASC", "external_product_id ASC")
        .group_by(&:internal_order_id)
    end

    private

    def pagination_value(value, default:)
      return default if value.nil?
      return unless value.is_a?(String) && POSITIVE_INTEGER.match?(value)

      value.to_i
    end
  end
end
