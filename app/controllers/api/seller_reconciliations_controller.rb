module Api
  class SellerReconciliationsController < ApplicationController
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/

    protect_from_forgery with: :null_session

    def create
      seller = Seller.find_by(seller_id: params[:seller_id])
      return render json: { error: "seller_not_found" }, status: :not_found unless seller

      dates = parsed_dates
      return render_invalid_parameters unless dates && dates[:start_date] <= dates[:end_date]

      reconciliation = seller.seller_reconciliations.create!(dates)
      return render_enqueue_failure(reconciliation) unless enqueue(reconciliation)

      render json: {
        reconciliation_id: reconciliation.reconciliation_id,
        seller_id: seller.seller_id,
        status: reconciliation.status
      }, status: :accepted
    end

    private

    def parsed_dates
      permitted = params.permit(:start_date, :end_date)
      start_date = parse_date(permitted[:start_date])
      end_date = parse_date(permitted[:end_date])
      return unless start_date && end_date

      { start_date: start_date, end_date: end_date }
    end

    def parse_date(value)
      return unless value.is_a?(String) && ISO_DATE.match?(value)

      Date.iso8601(value)
    rescue Date::Error
      nil
    end

    def enqueue(reconciliation)
      GenerateSellerReconciliationJob.perform_later(reconciliation.reconciliation_id)
      true
    rescue StandardError => error
      Rails.logger.error(
        "Could not enqueue seller reconciliation #{reconciliation.reconciliation_id} (#{error.class})"
      )
      false
    end

    def render_enqueue_failure(reconciliation)
      reconciliation.fail!
      render json: {
        error: "reconciliation_enqueue_failed",
        reconciliation_id: reconciliation.reconciliation_id
      }, status: :service_unavailable
    end

    def render_invalid_parameters
      render json: { error: "invalid_reconciliation_parameters" }, status: :unprocessable_entity
    end
  end
end
