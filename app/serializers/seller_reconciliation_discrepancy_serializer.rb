class SellerReconciliationDiscrepancySerializer
  def initialize(discrepancy)
    @discrepancy = discrepancy
  end

  def as_json(*)
    {
      order_id: discrepancy.external_order_id,
      issue_type: discrepancy.issue_type,
      expected_value: decimal_string(discrepancy.expected_value),
      paid_value: decimal_string(discrepancy.paid_value),
      difference: decimal_string(discrepancy.difference)
    }
  end

  private

  attr_reader :discrepancy

  def decimal_string(value)
    whole, fractional = value.round(2).to_s("F").split(".", 2)
    "#{whole}.#{fractional.to_s.ljust(2, "0")[0, 2]}"
  end
end
