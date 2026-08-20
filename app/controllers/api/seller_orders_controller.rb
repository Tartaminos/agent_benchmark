module Api
  class SellerOrdersController < ActionController::API
    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 100

    def index
      page = pagination_value(:page, DEFAULT_PAGE)
      per_page = pagination_value(:per_page, DEFAULT_PER_PAGE)

      unless page && per_page && per_page <= MAX_PER_PAGE
        return render json: { error: "invalid_pagination" }, status: :unprocessable_content
      end

      seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless seller

      total_orders = seller_order_items(seller).distinct.count(:order_id)
      orders = paginated_orders(seller, page, per_page, total_orders).to_a
      products_by_order = products_by_order(seller, orders.map(&:id))

      render json: {
        seller_id: seller.seller_id,
        page: page,
        per_page: per_page,
        total_orders: total_orders,
        orders: orders.map { |order| order_json(order, products_by_order[order.id]) }
      }
    end

    private

    def pagination_value(name, default)
      return default unless params.key?(name)

      value = params[name]
      return unless value.is_a?(String) && value.match?(/\A\d+\z/)

      number = value.to_i
      number if number.positive?
    end

    def seller_order_items(seller)
      OrderItem.where(seller_id: seller.id)
    end

    def paginated_orders(seller, page, per_page, total_orders)
      Order
        .joins(:order_items)
        .where(order_items: { seller_id: seller.id })
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
        .limit(per_page)
        .offset([ (page - 1) * per_page, total_orders ].min)
    end

    def products_by_order(seller, order_ids)
      return {} if order_ids.empty?

      rows = OrderItem
        .joins(:product)
        .where(seller_id: seller.id, order_id: order_ids)
        .distinct
        .order(:order_id, "products.product_id")
        .pluck(:order_id, "products.product_id", "products.category_name")

      rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(order_id, product_id, category_name), products|
        products[order_id] << { product_id: product_id, category_name: category_name }
      end
    end

    def order_json(order, products)
      items_value = order[:items_value]
      freight_value = order[:freight_value]

      {
        order_id: order.order_id,
        status: order.status,
        purchase_at: order.purchase_at.utc.iso8601(3),
        item_count: order[:item_count].to_i,
        items_value: money(items_value),
        freight_value: money(freight_value),
        total_value: money(items_value + freight_value),
        products: products
      }
    end

    def money(value)
      whole, fractional = value.round(2).to_s("F").split(".", 2)

      "#{whole}.#{fractional.to_s.ljust(2, "0")[0, 2]}"
    end
  end
end
