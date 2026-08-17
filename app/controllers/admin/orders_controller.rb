module Admin
  class OrdersController < ApplicationController
    PER_PAGE = 10
    ORDER_STATUSES = %w[approved canceled created delivered invoiced processing shipped unavailable].freeze
    DELIVERY_STATUSES = %w[pending on_time late].freeze
    CUSTOMER_STATES = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].sort.freeze
    FILTER_KEYS = %i[order_id list_order_id status delivery_status customer_state purchase_from purchase_to sort page].freeze

    def index
      prepare_filters
      @page = parsed_page
      if @filter_errors.any?
        prepare_invalid_results
        return render status: :unprocessable_content
      end

      query = OrdersQuery.new(@filters)
      @total_orders = query.relation.count
      @total_pages = [ (@total_orders.to_f / PER_PAGE).ceil, 1 ].max
      @page = [ @page, @total_pages ].min
      @orders = query.page(page: @page, per_page: PER_PAGE, direction: @filters[:sort]).to_a
      @totals_by_order_id = totals_for(@orders.map(&:id))
      @dataset_empty = @total_orders.zero? && !Order.exists?
      @pagination_pages = pagination_pages(@page, @total_pages)
      @query_params = query_params
      @filters_active = @filters.except(:sort).values.any?(&:present?)
    end

    def show
      prepare_filters
      @page = parsed_page
      external_order_id = params[:order_id].to_s.strip
      @order = Order.includes(:customer).find_by(order_id: external_order_id)
      @query_params = query_params

      if @order
        item_totals = OrderItem.where(order_id: @order.id).pick(
          Arel.sql("COALESCE(SUM(price), 0)"),
          Arel.sql("COALESCE(SUM(freight_value), 0)")
        )
        @item_total, @freight_total = item_totals
        @paid_total = OrderPayment.where(order_id: @order.id).sum(:payment_value)
      else
        render status: :not_found
      end
    end

    private

    def prepare_filters
      permitted = params.permit(*FILTER_KEYS)
      @filter_errors = []
      order_id_filter = action_name == "show" ? permitted[:list_order_id] : permitted[:order_id]
      @filters = {
        order_id: order_id_filter.to_s.strip.presence,
        status: permitted[:status].to_s.presence,
        delivery_status: permitted[:delivery_status].to_s.presence,
        customer_state: permitted[:customer_state].to_s.upcase.presence,
        purchase_from: parse_date(permitted[:purchase_from], "Start date"),
        purchase_to: parse_date(permitted[:purchase_to], "End date"),
        sort: permitted[:sort].to_s.presence || "desc"
      }

      validate_choice(:status, ORDER_STATUSES, "Order status")
      validate_choice(:delivery_status, DELIVERY_STATUSES, "Delivery status")
      validate_choice(:customer_state, CUSTOMER_STATES, "Customer state")
      validate_choice(:sort, %w[asc desc], "Sort direction")

      if @filters[:purchase_from] && @filters[:purchase_to] && @filters[:purchase_from] > @filters[:purchase_to]
        @filter_errors << "Start date must be on or before end date."
      end
    end

    def parse_date(value, label)
      return if value.blank?

      raw = value.to_s
      unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        @filter_errors << "#{label} must be a valid date."
        return
      end

      Date.iso8601(raw)
    rescue Date::Error
      @filter_errors << "#{label} must be a valid date."
      nil
    end

    def validate_choice(key, choices, label)
      value = @filters[key]
      @filter_errors << "#{label} is not valid." if value.present? && !choices.include?(value)
    end

    def parsed_page
      value = params[:page].to_s
      return 1 if value.blank?
      return value.to_i if value.match?(/\A[1-9]\d*\z/) && value.to_i <= 1_000_000

      @filter_errors << "Page must be a positive number."
      1
    end

    def totals_for(order_ids)
      return {} if order_ids.empty?

      rows = OrderItem
        .where(order_id: order_ids)
        .group(:order_id)
        .pluck(
          :order_id,
          Arel.sql("COALESCE(SUM(price), 0)"),
          Arel.sql("COALESCE(SUM(freight_value), 0)")
        )

      rows.to_h { |order_id, item_total, freight_total| [ order_id, item_total + freight_total ] }
    end

    def prepare_invalid_results
      @orders = []
      @total_orders = 0
      @total_pages = 1
      @page = 1
      @totals_by_order_id = {}
      @dataset_empty = false
      @pagination_pages = [ 1 ]
      @query_params = query_params
    end

    def query_params
      {
        order_id: @filters[:order_id],
        status: @filters[:status],
        delivery_status: @filters[:delivery_status],
        customer_state: @filters[:customer_state],
        purchase_from: params[:purchase_from].to_s.presence,
        purchase_to: params[:purchase_to].to_s.presence,
        sort: @filters[:sort],
        page: @page
      }.compact
    end

    def pagination_pages(current, total)
      return (1..total).to_a if total <= 7

      ([ 1, total ] + ((current - 2)..(current + 2)).to_a).select { |page| page.between?(1, total) }.uniq.sort
    end
  end
end
