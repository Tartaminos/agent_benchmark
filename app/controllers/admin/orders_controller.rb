module Admin
  class OrdersController < ApplicationController
    PER_PAGE_OPTIONS = [ 10, 25, 50 ].freeze
    DEFAULT_PER_PAGE = 10
    FILTER_KEYS = %i[order_id order_status delivery_status customer_state purchase_from purchase_to].freeze

    before_action :prepare_filters

    def index
      load_orders
    end

    def show
      load_orders
      load_order_details
      render :index, status: (@order ? :ok : :not_found)
    end

    private

    def prepare_filters
      @filter_errors = []
      @filters = FILTER_KEYS.to_h { |key| [ key, scalar_param(key) ] }
      @sort = %w[asc desc].include?(scalar_param(:sort)) ? scalar_param(:sort) : "desc"
      @per_page = integer_param(:per_page, DEFAULT_PER_PAGE, allowed: PER_PAGE_OPTIONS)
      @page = integer_param(:page, 1)

      @purchase_from = parse_date(:purchase_from)
      @purchase_to = parse_date(:purchase_to)
      if @purchase_from && @purchase_to && @purchase_from > @purchase_to
        @filter_errors << "Purchase date from must be on or before purchase date to."
      end

      validate_delivery_status
      @query_params = @filters.compact_blank.merge(sort: @sort, per_page: @per_page)
    end

    def load_orders
      @order_statuses = Order.distinct.order(:status).pluck(:status)
      @customer_states = Customer.distinct.order(:state).pluck(:state)

      relation = filtered_relation
      @total_orders = @filter_errors.empty? ? relation.except(:select, :order).count : 0
      @total_pages = (@total_orders.to_f / @per_page).ceil

      offset = (@page - 1) * @per_page
      @orders = if @filter_errors.any? || offset > (2**63) - 1
        []
      else
        relation
          .order(purchase_at: @sort.to_sym, order_id: :asc)
          .limit(@per_page)
          .offset(offset)
          .to_a
      end

      @order_totals = load_page_totals
    end

    def filtered_relation
      relation = Order.joins(:customer)
        .with_delivery_status
        .select("customers.state AS customer_state")

      if @filters[:order_id].present?
        pattern = ActiveRecord::Base.sanitize_sql_like(@filters[:order_id])
        relation = relation.where("orders.order_id ILIKE ?", "%#{pattern}%")
      end
      relation = relation.where(status: @filters[:order_status]) if @filters[:order_status].present?
      relation = relation.for_delivery_status(@filters[:delivery_status]) if @filters[:delivery_status].present?
      relation = relation.where(customers: { state: @filters[:customer_state] }) if @filters[:customer_state].present?
      relation = relation.where("orders.purchase_at >= ?", @purchase_from.beginning_of_day) if @purchase_from
      relation = relation.where("orders.purchase_at < ?", @purchase_to.next_day.beginning_of_day) if @purchase_to
      relation
    end

    def load_page_totals
      ids = @orders.map(&:id)
      return {} if ids.empty?

      OrderItem.where(order_id: ids)
        .group(:order_id)
        .pluck(:order_id, Arel.sql("COALESCE(SUM(price + freight_value), 0)"))
        .to_h
    end

    def load_order_details
      @order = Order.with_delivery_status.includes(:customer).find_by(order_id: params[:selected_order_id])
      return unless @order

      item_totals = OrderItem.where(order_id: @order.id)
        .pick(
          Arel.sql("COALESCE(SUM(price), 0)"),
          Arel.sql("COALESCE(SUM(freight_value), 0)")
        )
      items = item_totals&.first || BigDecimal("0")
      freight = item_totals&.second || BigDecimal("0")
      @detail_totals = {
        items:,
        freight:,
        order: items + freight,
        paid: OrderPayment.where(order_id: @order.id).sum(:payment_value)
      }
    end

    def scalar_param(name)
      value = params[name]
      return if value.blank?

      unless value.is_a?(String)
        @filter_errors << "Invalid value for #{name.to_s.humanize.downcase}."
        return
      end
      value.strip.presence
    end

    def integer_param(name, default, allowed: nil)
      value = scalar_param(name)
      return default unless value
      return value.to_i if value.match?(/\A[1-9]\d*\z/) && (!allowed || allowed.include?(value.to_i))

      @filter_errors << "Invalid value for #{name.to_s.humanize.downcase}."
      default
    end

    def parse_date(name)
      value = @filters[name]
      return unless value

      Date.iso8601(value)
    rescue Date::Error
      @filter_errors << "#{name == :purchase_from ? 'Purchase date from' : 'Purchase date to'} is not a valid date."
      nil
    end

    def validate_delivery_status
      value = @filters[:delivery_status]
      return if value.blank? || Order::DELIVERY_STATUSES.include?(value)

      @filter_errors << "Delivery status is not valid."
    end
  end
end
