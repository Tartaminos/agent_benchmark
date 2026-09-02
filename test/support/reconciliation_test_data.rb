module ReconciliationTestData
  def build_reconciliation_data
    @reconciliation_sequence = 0
    @reconciliation_seller = create_reconciliation_seller("target")
    @other_reconciliation_seller = create_reconciliation_seller("other")
    @reconciliation_customer = Customer.create!(
      customer_id: reconciliation_external_id("customer"),
      customer_unique_id: reconciliation_external_id("unique"),
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  def create_reconciliation_seller(label)
    Seller.create!(
      seller_id: reconciliation_external_id("seller_#{label}"),
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  def create_reconciliation(start_date: Date.new(2018, 1, 1), end_date: Date.new(2018, 1, 31),
                            status: "pending", processing_token: nil)
    @reconciliation_seller.seller_reconciliations.create!(
      start_date: start_date,
      end_date: end_date,
      status: status,
      processing_token: processing_token
    )
  end

  def create_reconciliation_order(purchase_at:, seller: @reconciliation_seller,
                                  items:, payments: [])
    order = Order.create!(
      order_id: reconciliation_external_id("order"),
      customer: @reconciliation_customer,
      status: "delivered",
      purchase_at: purchase_at,
      estimated_delivery_at: purchase_at + 7.days
    )

    items.each_with_index do |item, index|
      product = Product.create!(product_id: reconciliation_external_id("product"))
      OrderItem.create!(
        order: order,
        product: product,
        seller: item.fetch(:seller, seller),
        order_item_id: index + 1,
        shipping_limit_at: purchase_at + 1.day,
        price: item.fetch(:price),
        freight_value: item.fetch(:freight)
      )
    end

    payments.each_with_index do |value, index|
      OrderPayment.create!(
        order: order,
        payment_sequential: index + 1,
        payment_type: "credit_card",
        payment_installments: 1,
        payment_value: value
      )
    end

    order
  end

  def complete_reconciliation(reconciliation, summary = {})
    defaults = {
      orders_checked: 0,
      matched_orders: 0,
      inconsistent_orders: 0,
      missing_payment_orders: 0,
      amount_mismatch_orders: 0,
      expected_value: 0,
      paid_value: 0,
      difference: 0
    }
    reconciliation.update!(defaults.merge(summary).merge(status: "completed", processing_token: nil))
    reconciliation
  end

  def create_discrepancy(reconciliation, order_id:, issue_type: "amount_mismatch",
                         expected_value: 10, paid_value: 9, difference: -1)
    reconciliation.discrepancies.create!(
      external_order_id: order_id,
      issue_type: issue_type,
      expected_value: expected_value,
      paid_value: paid_value,
      difference: difference
    )
  end

  private

  def reconciliation_external_id(prefix)
    @reconciliation_sequence ||= 0
    @reconciliation_sequence += 1
    "r#{Process.pid}_#{prefix}_#{@reconciliation_sequence}"[0, 32]
  end
end
