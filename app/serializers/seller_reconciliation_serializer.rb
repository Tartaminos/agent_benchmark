class SellerReconciliationSerializer
  def initialize(reconciliation)
    @reconciliation = reconciliation
  end

  def as_json(*)
    response = {
      reconciliation_id: reconciliation.reconciliation_id,
      seller_id: reconciliation.seller.seller_id,
      status: reconciliation.status,
      start_date: reconciliation.start_date.iso8601,
      end_date: reconciliation.end_date.iso8601
    }
    response[:summary] = summary if reconciliation.status == "completed"
    response
  end

  private

  attr_reader :reconciliation

  def summary
    {
      orders_checked: reconciliation.orders_checked,
      matched_orders: reconciliation.matched_orders,
      inconsistent_orders: reconciliation.inconsistent_orders,
      missing_payment_orders: reconciliation.missing_payment_orders,
      amount_mismatch_orders: reconciliation.amount_mismatch_orders,
      expected_value: decimal_string(reconciliation.expected_value),
      paid_value: decimal_string(reconciliation.paid_value),
      difference: decimal_string(reconciliation.difference),
      discrepancies_url: Rails.application.routes.url_helpers.api_reconciliation_discrepancies_path(
        reconciliation_id: reconciliation.reconciliation_id
      )
    }
  end

  def decimal_string(value)
    whole, fractional = value.round(2).to_s("F").split(".", 2)
    "#{whole}.#{fractional.to_s.ljust(2, "0")[0, 2]}"
  end
end
