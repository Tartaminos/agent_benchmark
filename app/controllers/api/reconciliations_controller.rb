module Api
  class ReconciliationsController < ActionController::API
    def show
      reconciliation = SellerReconciliation.includes(:seller).find_by(
        reconciliation_id: params[:reconciliation_id]
      )
      return render json: { error: "reconciliation_not_found" }, status: :not_found unless reconciliation

      render json: SellerReconciliationSerializer.new(reconciliation).as_json
    end
  end
end
