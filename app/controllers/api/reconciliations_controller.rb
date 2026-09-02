module Api
  class ReconciliationsController < ApplicationController
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100
    POSITIVE_INTEGER = /\A[1-9]\d*\z/

    before_action :load_reconciliation

    def show
      payload = base_payload
      payload[:summary] = summary_payload if @reconciliation.completed?
      render json: payload
    end

    def discrepancies
      unless @reconciliation.completed?
        return render json: { error: "reconciliation_not_completed" }, status: :conflict
      end

      pagination = parsed_pagination
      return render_invalid_pagination unless pagination

      relation = @reconciliation.reconciliation_discrepancies.order(:external_order_id)
      total_count = relation.count
      per_page = pagination.fetch(:per_page)
      total_pages = (total_count + per_page - 1) / per_page
      records = discrepancy_page(relation, pagination, total_pages)

      render json: {
        reconciliation_id: @reconciliation.reconciliation_id,
        discrepancies: records.map { |record| discrepancy_payload(record) },
        pagination: {
          page: pagination.fetch(:page),
          per_page: pagination.fetch(:per_page),
          total_count: total_count,
          total_pages: total_pages
        }
      }
    end

    private

    def load_reconciliation
      @reconciliation = SellerReconciliation.includes(:seller).find_by(
        reconciliation_id: params[:reconciliation_id]
      )
      render json: { error: "reconciliation_not_found" }, status: :not_found unless @reconciliation
    end

    def base_payload
      {
        reconciliation_id: @reconciliation.reconciliation_id,
        seller_id: @reconciliation.seller.seller_id,
        status: @reconciliation.status,
        start_date: @reconciliation.start_date.iso8601,
        end_date: @reconciliation.end_date.iso8601
      }
    end

    def summary_payload
      {
        orders_checked: @reconciliation.orders_checked,
        matched_orders: @reconciliation.matched_orders,
        inconsistent_orders: @reconciliation.inconsistent_orders,
        missing_payment_orders: @reconciliation.missing_payment_orders,
        amount_mismatch_orders: @reconciliation.amount_mismatch_orders,
        expected_value: decimal(@reconciliation.expected_value),
        paid_value: decimal(@reconciliation.paid_value),
        difference: decimal(@reconciliation.difference),
        discrepancies_url: discrepancies_api_reconciliation_path(
          reconciliation_id: @reconciliation.reconciliation_id
        )
      }
    end

    def parsed_pagination
      page = positive_integer(params[:page], default: 1)
      per_page = positive_integer(params[:per_page], default: DEFAULT_PER_PAGE)
      return unless page && per_page && per_page <= MAX_PER_PAGE

      { page: page, per_page: per_page }
    end

    def positive_integer(value, default:)
      return default if value.nil?
      return unless value.is_a?(String) && POSITIVE_INTEGER.match?(value)

      Integer(value, 10)
    rescue ArgumentError
      nil
    end

    def discrepancy_page(relation, pagination, total_pages)
      page = pagination.fetch(:page)
      return [] if total_pages.zero? || page > total_pages

      relation.offset((page - 1) * pagination.fetch(:per_page))
              .limit(pagination.fetch(:per_page))
              .to_a
    end

    def discrepancy_payload(discrepancy)
      {
        order_id: discrepancy.external_order_id,
        issue_type: discrepancy.issue_type,
        expected_value: decimal(discrepancy.expected_value),
        paid_value: decimal(discrepancy.paid_value),
        difference: decimal(discrepancy.difference)
      }
    end

    def decimal(value)
      format("%.2f", BigDecimal(value.to_s))
    end

    def render_invalid_pagination
      render json: { error: "invalid_pagination" }, status: :unprocessable_entity
    end
  end
end
