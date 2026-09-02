class GenerateSellerReconciliationJob < ApplicationJob
  queue_as :default

  def perform(reconciliation_id)
    reconciliation = SellerReconciliation.find_by(reconciliation_id: reconciliation_id)
    return unless reconciliation&.claim_for_processing!

    SellerReconciliationGenerator.new(reconciliation).call
  rescue StandardError => error
    Rails.logger.error(
      "Seller reconciliation #{reconciliation_id} failed (#{error.class}): #{error.message}"
    )
    reconciliation&.fail!
  end
end
