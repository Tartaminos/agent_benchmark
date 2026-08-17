module Api
  class SellerOrdersController < ApplicationController
    MAX_PER_PAGE = 100
    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 20

    def index
      pagination = pagination_params
      return render json: { error: "invalid_pagination" }, status: :unprocessable_content unless pagination

      @page, @per_page = pagination
      @seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless @seller

      @total_orders = seller_order_items.distinct.count(:order_id)
      offset = (@page - 1) * @per_page
      @orders = offset >= @total_orders ? [] : seller_orders.offset(offset).limit(@per_page)
      @products_by_order_id = products_by_order_id(@orders.map(&:id))
    end

    private

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

    def seller_order_items
      OrderItem.where(seller_id: @seller.id)
    end

    def seller_orders
      Order
        .joins(:order_items)
        .where(order_items: { seller_id: @seller.id })
        .select(
          "orders.id",
          "orders.order_id",
          "orders.status",
          "orders.purchase_at",
          "COUNT(order_items.id) AS item_count",
          "SUM(order_items.price) AS items_value",
          "SUM(order_items.freight_value) AS freight_value"
        )
        .group("orders.id")
        .order(purchase_at: :desc, order_id: :asc)
    end

    def products_by_order_id(order_ids)
      return {} if order_ids.empty?

      rows = OrderItem
        .joins(:product)
        .where(seller_id: @seller.id, order_id: order_ids)
        .select(
          "order_items.order_id",
          "products.product_id AS external_product_id",
          "products.category_name AS product_category_name"
        )
        .distinct
        .order("order_items.order_id ASC", "products.product_id ASC")

      rows.group_by(&:order_id)
    end
  end
end
