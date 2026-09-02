class ProcessSellerReconciliationJob < ApplicationJob
  def perform(reconciliation_id)
    processing_token = SecureRandom.uuid
    reconciliation = claim(reconciliation_id, processing_token)
    return unless reconciliation

    SellerReconciliationProcessor.new(
      reconciliation_id: reconciliation.id,
      processing_token: processing_token
    ).process
  rescue StandardError => error
    fail_claim(reconciliation_id, processing_token) if processing_token
    Rails.logger.error(
      "Seller reconciliation processing failed reconciliation_id=#{reconciliation_id} " \
        "error=#{error.class}: #{error.message}"
    )
    raise
  end

  private

  def claim(reconciliation_id, processing_token)
    reconciliation = SellerReconciliation.find_by(reconciliation_id: reconciliation_id)
    return unless reconciliation

    claimed = SellerReconciliation
      .where(id: reconciliation.id, status: %w[pending failed])
      .update_all(
        status: "processing",
        processing_token: processing_token,
        updated_at: Time.current
      )
    reconciliation.reload if claimed == 1
  end

  def fail_claim(reconciliation_id, processing_token)
    SellerReconciliation.transaction do
      reconciliation = SellerReconciliation
        .lock
        .find_by(
          reconciliation_id: reconciliation_id,
          status: "processing",
          processing_token: processing_token
        )
      next unless reconciliation

      reconciliation.discrepancies.delete_all
      reconciliation.update!(status: "failed", processing_token: nil)
    end
  end
end
