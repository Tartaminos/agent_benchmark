module Admin
  class OrdersController < ApplicationController
    ORDER_STATUSES = %w[
      approved canceled created delivered invoiced processing shipped unavailable
    ].freeze
    CUSTOMER_STATES = %w[
      AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO
    ].freeze
    SORT_DIRECTIONS = %w[asc desc].freeze
    PER_PAGE = 10
    MAX_PAGE = 1_000_000
    POSITIVE_INTEGER = /\A[1-9]\d*\z/

    def index
      @filter_errors = []
      @invalid_filter_fields = []
      @filters = filter_values
      @sort = allowed_sort
      @page = allowed_page

      orders = filtered_orders
      @total_orders = orders.count
      @total_pages = (@total_orders.to_f / PER_PAGE).ceil
      @page = @total_pages if @total_pages.positive? && @page > @total_pages

      @orders = orders
        .includes(:customer)
        .order(purchase_at: @sort, order_id: :asc)
        .offset((@page - 1) * PER_PAGE)
        .limit(PER_PAGE)
        .to_a

      @order_totals = page_order_totals
      @dataset_empty = @total_orders.zero? && !Order.exists?
      @filters_active = @filters.values.any?(&:present?)
      @navigation_params = @filters.compact_blank.merge(sort: @sort)

      load_order_details
    end

    private

    def filter_values
      {
        order_id: scalar_param(:order_id),
        status: scalar_param(:status),
        delivery_status: scalar_param(:delivery_status),
        customer_state: scalar_param(:customer_state),
        start_date: scalar_param(:start_date),
        end_date: scalar_param(:end_date)
      }
    end

    def scalar_param(name)
      value = params[name]
      return "" if value.nil?
      return value.strip if value.is_a?(String)

      @filter_errors << "The #{name.to_s.humanize.downcase} filter is invalid."
      @invalid_filter_fields << name
      ""
    end

    def allowed_sort
      value = params[:sort]
      return "desc" if value.nil?
      return value if value.is_a?(String) && SORT_DIRECTIONS.include?(value)

      @filter_errors << "The selected sort direction is invalid."
      @invalid_filter_fields << :sort
      "desc"
    end

    def allowed_page
      value = params[:page]
      return 1 if value.nil?
      return value.to_i if value.is_a?(String) && POSITIVE_INTEGER.match?(value) && value.to_i <= MAX_PAGE

      @filter_errors << "The requested page is invalid. Showing the first page instead."
      1
    end

    def filtered_orders
      scope = Order.joins(:customer)

      scope = scope.where(order_id: @filters[:order_id]) if @filters[:order_id].present?
      scope = apply_allowed_filter(scope, :status, ORDER_STATUSES, @filters[:status])
      scope = apply_allowed_filter(scope, "customers.state", CUSTOMER_STATES, @filters[:customer_state])

      delivery_status = @filters[:delivery_status]
      if delivery_status.present?
        if Order::DELIVERY_STATUSES.include?(delivery_status)
          scope = scope.with_delivery_status(delivery_status)
        else
          @filter_errors << "The selected delivery status is invalid."
          @invalid_filter_fields << :delivery_status
        end
      end

      apply_date_range(scope)
    end

    def apply_allowed_filter(scope, column, allowed_values, value)
      return scope if value.blank?
      return scope.where(column => value) if allowed_values.include?(value)

      @filter_errors << "The selected #{column.to_s.split('.').last.humanize.downcase} is invalid."
      @invalid_filter_fields << (column == :status ? :status : :customer_state)
      scope
    end

    def apply_date_range(scope)
      start_date = parse_date(@filters[:start_date])
      end_date = parse_date(@filters[:end_date])

      if (start_date && end_date && start_date > end_date) ||
          (@filters[:start_date].present? && start_date.nil?) ||
          (@filters[:end_date].present? && end_date.nil?)
        @filter_errors << "Enter a valid purchase date range. The end date cannot be before the start date."
        @invalid_filter_fields.concat(%i[start_date end_date])
        return scope
      end

      scope = scope.where("orders.purchase_at >= ?", start_date.beginning_of_day) if start_date
      scope = scope.where("orders.purchase_at < ?", end_date.next_day.beginning_of_day) if end_date
      scope
    end

    def parse_date(value)
      Date.iso8601(value) if value.present?
    rescue Date::Error
      nil
    end

    def page_order_totals
      return {} if @orders.empty?

      OrderItem
        .where(order_id: @orders.map(&:id))
        .group(:order_id)
        .sum("order_items.price + order_items.freight_value")
    end

    def load_order_details
      details_order_id = params[:details_order_id]
      return if details_order_id.nil?

      unless details_order_id.is_a?(String) && details_order_id.present? && details_order_id.length <= 32
        @detail_unavailable = true
        return
      end

      @detail_order = Order.includes(:customer).find_by(order_id: details_order_id)
      unless @detail_order
        @detail_unavailable = true
        return
      end

      item_totals = OrderItem
        .where(order_id: @detail_order.id)
        .pick(Arel.sql("COALESCE(SUM(price), 0)"), Arel.sql("COALESCE(SUM(freight_value), 0)"))

      @detail_items_total, @detail_freight_total = item_totals.map { |value| BigDecimal(value.to_s) }
      @detail_order_total = @detail_items_total + @detail_freight_total
      @detail_paid_total = OrderPayment.where(order_id: @detail_order.id).sum(:payment_value)
    end
  end
end
