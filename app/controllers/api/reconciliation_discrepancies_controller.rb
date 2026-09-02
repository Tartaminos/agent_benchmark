module Api
  class ReconciliationDiscrepanciesController < ActionController::API
    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    def index
      reconciliation = SellerReconciliation.find_by(reconciliation_id: params[:reconciliation_id])
      return render json: { error: "reconciliation_not_found" }, status: :not_found unless reconciliation
      unless reconciliation.status == "completed"
        return render json: { error: "reconciliation_not_ready" }, status: :conflict
      end

      pagination = parsed_pagination
      return render json: { error: "invalid_pagination" }, status: :unprocessable_content unless pagination

      render json: discrepancy_response(reconciliation, **pagination)
    end

    private

    def parsed_pagination
      page = positive_integer_param(:page, DEFAULT_PAGE)
      per_page = positive_integer_param(:per_page, DEFAULT_PER_PAGE)
      return unless page && per_page && per_page <= MAX_PER_PAGE

      { page: page, per_page: per_page }
    end

    def positive_integer_param(name, default)
      value = params[name]
      return default if value.nil?
      return unless value.is_a?(String) && value.match?(/\A\d+\z/)

      parsed = value.to_i
      parsed if parsed.positive?
    end

    def discrepancy_response(reconciliation, page:, per_page:)
      scope = reconciliation.discrepancies.order(:external_order_id)
      total_count = scope.count
      offset = (page - 1) * per_page
      discrepancies = if offset >= total_count
        []
      else
        scope.limit(per_page).offset(offset).map do |discrepancy|
          SellerReconciliationDiscrepancySerializer.new(discrepancy).as_json
        end
      end

      {
        page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count + per_page - 1) / per_page,
        discrepancies: discrepancies
      }
    end
  end
end
