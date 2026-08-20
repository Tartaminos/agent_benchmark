require "test_helper"

class OrderTest < ActiveSupport::TestCase
  setup do
    @customer = Customer.create!(
      customer_id: "classification_customer_000001",
      customer_unique_id: "classification_unique_0000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  test "derives pending, on-time including equality, and late delivery statuses" do
    estimated_at = Time.utc(2024, 2, 10, 12)
    pending = create_order("classification_pending_000001", estimated_at:, delivered_at: nil)
    early = create_order("classification_early_00000001", estimated_at:, delivered_at: estimated_at - 1.second)
    boundary = create_order("classification_boundary_00001", estimated_at:, delivered_at: estimated_at)
    late = create_order("classification_late_000000001", estimated_at:, delivered_at: estimated_at + 1.second)

    assert_equal "pending", pending.delivery_status
    assert_equal "on_time", early.delivery_status
    assert_equal "on_time", boundary.delivery_status
    assert_equal "late", late.delivery_status
  end

  test "filters each classification in an unloaded database relation" do
    estimated_at = Time.utc(2024, 2, 10, 12)
    pending = create_order("scope_pending_000000000000001", estimated_at:, delivered_at: nil)
    on_time = create_order("scope_on_time_0000000000001", estimated_at:, delivered_at: estimated_at)
    late = create_order("scope_late_00000000000000001", estimated_at:, delivered_at: estimated_at + 1.second)

    {
      "pending" => pending.order_id,
      "on_time" => on_time.order_id,
      "late" => late.order_id
    }.each do |status, expected_order_id|
      relation = Order.with_delivery_status(status)

      assert_kind_of ActiveRecord::Relation, relation
      refute relation.loaded?, "expected #{status} filtering to remain in SQL until evaluated"
      assert_equal [ expected_order_id ], relation.pluck(:order_id)
    end
  end

  private

  def create_order(order_id, estimated_at:, delivered_at:)
    Order.create!(
      order_id: order_id,
      customer: @customer,
      status: "delivered",
      purchase_at: Time.utc(2024, 2, 1),
      estimated_delivery_at: estimated_at,
      delivered_customer_at: delivered_at
    )
  end
end
