module Api
  class SellerOrdersController < ApplicationController
    MAX_PER_PAGE = 100
    MAX_DATABASE_OFFSET = (2**63) - 1
    POSITIVE_INTEGER = /\A[1-9][0-9]*\z/

    def index
      return render_invalid_pagination unless valid_pagination?

      @page = pagination_value(:page, 1)
      @per_page = pagination_value(:per_page, 20)
      @seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless @seller

      seller_items = OrderItem.where(seller_id: @seller.id)
      @total_orders = seller_items.distinct.count(:order_id)
      @orders = load_orders(seller_items)
      @products_by_order = load_products(@orders.map(&:internal_order_id))
    end

    private

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

    def load_orders(seller_items)
      offset = (@page - 1) * @per_page
      return Order.none.to_a if offset > MAX_DATABASE_OFFSET

      Order
        .joins(:order_items)
        .merge(seller_items)
        .select(
          "orders.id AS internal_order_id",
          "orders.order_id",
          "orders.status",
          "orders.purchase_at",
          "COUNT(order_items.id) AS item_count",
          "SUM(order_items.price) AS items_value",
          "SUM(order_items.freight_value) AS freight_value",
          "SUM(order_items.price + order_items.freight_value) AS total_value"
        )
        .group("orders.id")
        .order(purchase_at: :desc, order_id: :asc)
        .limit(@per_page)
        .offset(offset)
        .to_a
    end

    def load_products(order_ids)
      return {} if order_ids.empty?

      rows = OrderItem
        .joins(:product)
        .where(seller_id: @seller.id, order_id: order_ids)
        .distinct
        .order("order_items.order_id ASC", "products.product_id ASC")
        .pluck("order_items.order_id", "products.product_id", "products.category_name")

      rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(order_id, product_id, category_name), products|
        products[order_id] << { product_id: product_id, category_name: category_name }
      end
    end

    def render_invalid_pagination
      render json: { error: "invalid_pagination" }, status: :unprocessable_entity
    end
  end
end
