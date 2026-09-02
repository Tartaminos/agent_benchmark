module Admin
  class OrdersController < ApplicationController
    layout "admin"

    PAGE_SIZE = 25
    ORDER_STATUSES = Order::ORDER_STATUSES
    CUSTOMER_STATES = Customer::STATES
    SORT_DIRECTIONS = %w[asc desc].freeze
    FILTER_NAMES = %i[order_id status delivery_status customer_state purchased_from purchased_through].freeze

    def index
      initialize_filter_state

      if @errors.empty?
        load_orders
      else
        initialize_empty_results
        response.status = :unprocessable_content
      end
    end

    def show
      @order = Order.includes(:customer).find_by(order_id: params[:order_id])
      @return_query = listing_query_from_params

      if @order
        item_totals = OrderItem.where(order: @order).pick(
          Arel.sql("COALESCE(SUM(price), 0)"),
          Arel.sql("COALESCE(SUM(freight_value), 0)")
        )
        @totals = {
          items: item_totals.fetch(0),
          freight: item_totals.fetch(1),
          paid: OrderPayment.where(order: @order).sum(:payment_value)
        }
        @totals[:order] = @totals[:items] + @totals[:freight]
      else
        response.status = :not_found
      end
    end

    private

    def initialize_filter_state
      @errors = []
      @filters = FILTER_NAMES.to_h { |name| [ name, scalar_value(name) ] }
      @normalized_filters = @filters.transform_values { |value| value&.strip }
      @sort = normalized_allowed_value(:sort, SORT_DIRECTIONS, "Sort", default: "desc")
      @page = normalized_page

      validate_allowed_filter(:status, ORDER_STATUSES, "Order status")
      validate_allowed_filter(:delivery_status, Order::DELIVERY_STATUSES, "Delivery status")
      validate_allowed_filter(:customer_state, CUSTOMER_STATES, "Customer state")
      validate_order_id
      @purchased_from = parse_date(:purchased_from, "Purchased from")
      @purchased_through = parse_date(:purchased_through, "Purchased through")

      if @purchased_from && @purchased_through && @purchased_from > @purchased_through
        @errors << "Purchased from must be on or before purchased through."
      end

      @query_params = listing_query_from_values
    end

    def scalar_value(name)
      return "" unless params.key?(name)

      value = params[name]
      return value if value.is_a?(String)

      @errors << "#{name.to_s.humanize} must be a single value."
      ""
    end

    def normalized_allowed_value(name, allowed, label, default: "")
      return default unless params.key?(name)

      value = params[name]
      unless value.is_a?(String)
        @errors << "#{label} must be a single value."
        return default
      end

      normalized = value.strip
      return default if normalized.blank? && default.present?
      return normalized if allowed.include?(normalized)

      @errors << "#{label} is not valid."
      default
    end

    def normalized_page
      return 1 unless params.key?(:page)

      value = params[:page]
      unless value.is_a?(String) && value.match?(/\A[1-9][0-9]*\z/)
        @errors << "Page must be a positive whole number."
        return 1
      end

      value.to_i
    end

    def validate_allowed_filter(name, allowed, label)
      value = @normalized_filters[name]
      return if value.blank? || allowed.include?(value)

      @errors << "#{label} is not valid."
    end

    def validate_order_id
      value = @normalized_filters[:order_id]
      @errors << "Order ID is too long." if value && value.length > 64
    end

    def parse_date(name, label)
      value = @normalized_filters[name]
      return if value.blank?

      Date.iso8601(value)
    rescue Date::Error
      @errors << "#{label} must be a valid date."
      nil
    end

    def load_orders
      relation = filtered_orders
      @total_count = relation.count
      @total_pages = (@total_count.to_f / PAGE_SIZE).ceil
      @page = [ @page, [ @total_pages, 1 ].max ].min

      @orders = relation
        .preload(:customer)
        .order(purchase_at: @sort, order_id: :asc)
        .limit(PAGE_SIZE)
        .offset((@page - 1) * PAGE_SIZE)
        .to_a

      @order_totals = OrderItem
        .where(order_id: @orders.map(&:id))
        .group(:order_id)
        .sum(Arel.sql("price + freight_value"))

      @dataset_empty = @total_count.zero? && !Order.exists?
    end

    def filtered_orders
      relation = Order.all
      relation = relation.where(order_id: @normalized_filters[:order_id]) if @normalized_filters[:order_id].present?
      relation = relation.where(status: @normalized_filters[:status]) if @normalized_filters[:status].present?
      relation = relation.with_delivery_status(@normalized_filters[:delivery_status].presence)
      if @normalized_filters[:customer_state].present?
        relation = relation.joins(:customer).where(customers: { state: @normalized_filters[:customer_state] })
      end
      relation = relation.where(purchase_at: @purchased_from.beginning_of_day..) if @purchased_from
      relation = relation.where("orders.purchase_at < ?", (@purchased_through + 1.day).beginning_of_day) if @purchased_through
      relation
    end

    def initialize_empty_results
      @orders = []
      @order_totals = {}
      @total_count = 0
      @total_pages = 0
      @dataset_empty = false
    end

    def listing_query_from_values
      @normalized_filters
        .select { |_name, value| value.present? }
        .merge(sort: @sort)
    end

    def listing_query_from_params
      query_parameters = request.query_parameters
      query = FILTER_NAMES.to_h do |name|
        value = query_parameters[name.to_s]
        [ name, value.is_a?(String) ? value : "" ]
      end
      sort = query_parameters["sort"]
      query[:sort] = sort if sort.is_a?(String) && SORT_DIRECTIONS.include?(sort)
      page = query_parameters["page"]
      query[:page] = page if page.is_a?(String) && page.match?(/\A[1-9][0-9]*\z/)
      query.select { |_name, value| value.present? }
    end
  end
end
