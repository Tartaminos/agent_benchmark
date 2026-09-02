module Api
  class SellerReconciliationsController < ActionController::API
    def create
      dates = parsed_dates
      return render json: { error: "invalid_dates" }, status: :unprocessable_content unless dates

      seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless seller

      reconciliation = seller.seller_reconciliations.create!(dates)
      enqueue(reconciliation)
    end

    private

    def parsed_dates
      start_date = strict_date(params[:start_date])
      end_date = strict_date(params[:end_date])
      return unless start_date && end_date && start_date <= end_date

      { start_date: start_date, end_date: end_date }
    end

    def strict_date(value)
      return unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(value)
    rescue Date::Error
      nil
    end

    def enqueue(reconciliation)
      ProcessSellerReconciliationJob.perform_later(reconciliation.reconciliation_id)
    rescue StandardError => error
      SellerReconciliation
        .where(id: reconciliation.id, status: "pending")
        .update_all(status: "failed", updated_at: Time.current)
      Rails.logger.error(
        "Seller reconciliation enqueue failed reconciliation_id=#{reconciliation.reconciliation_id} " \
          "error=#{error.class}: #{error.message}"
      )
      render json: { error: "reconciliation_enqueue_failed" }, status: :service_unavailable
    else
      render json: SellerReconciliationSerializer.new(reconciliation).as_json, status: :accepted
    end
  end
end
