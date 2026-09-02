require "test_helper"
require_relative "../support/reconciliation_test_data"

class SellerReconciliationTest < ActiveSupport::TestCase
  include ReconciliationTestData

  setup { build_reconciliation_data }

  test "assigns an immutable public UUID and validates lifecycle fields" do
    reconciliation = create_reconciliation
    original_id = reconciliation.reconciliation_id
    original_seller_id = reconciliation.seller_id
    original_start_date = reconciliation.start_date

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, original_id)
    refute_equal reconciliation.id.to_s, original_id

    assert_raises(ActiveRecord::ReadonlyAttributeError) do
      reconciliation.update!(reconciliation_id: SecureRandom.uuid)
    end
    reconciliation.reload
    assert_raises(ActiveRecord::ReadonlyAttributeError) do
      reconciliation.update!(seller: @other_reconciliation_seller)
    end
    reconciliation.reload
    assert_raises(ActiveRecord::ReadonlyAttributeError) do
      reconciliation.update!(start_date: Date.new(2017, 1, 1))
    end
    reconciliation.reload
    assert_equal original_id, reconciliation.reconciliation_id
    assert_equal original_seller_id, reconciliation.seller_id
    assert_equal original_start_date, reconciliation.start_date

    invalid = @reconciliation_seller.seller_reconciliations.new(status: "unknown")
    refute invalid.valid?
    assert invalid.errors.of_kind?(:status, :inclusion)
    assert invalid.errors.of_kind?(:start_date, :blank)
    assert invalid.errors.of_kind?(:end_date, :blank)
  end

  test "database enforces summary count money status date and token invariants" do
    reconciliation = create_reconciliation

    assert_database_rejects { update_reconciliation(reconciliation, status: "unknown") }
    assert_database_rejects { update_reconciliation(reconciliation, start_date: Date.new(2018, 2, 1)) }
    assert_database_rejects { update_reconciliation(reconciliation, status: "processing", processing_token: nil) }
    assert_database_rejects { update_reconciliation(reconciliation, orders_checked: 1) }

    complete_reconciliation(reconciliation)
    assert_database_rejects { update_reconciliation(reconciliation, matched_orders: 1) }
    assert_database_rejects { update_reconciliation(reconciliation, difference: 1) }
    assert_database_rejects { update_reconciliation(reconciliation, status: "failed") }
  end

  test "discrepancy constraints enforce uniqueness classification arithmetic and foreign keys" do
    reconciliation = create_reconciliation
    create_discrepancy(reconciliation, order_id: "external_order")

    assert_database_rejects do
      insert_discrepancy(reconciliation, external_order_id: "external_order")
    end
    assert_database_rejects do
      insert_discrepancy(reconciliation, external_order_id: "bad_type", issue_type: "other")
    end
    assert_database_rejects do
      insert_discrepancy(reconciliation, external_order_id: "bad_missing", issue_type: "missing_payment",
        expected_value: 10, paid_value: 1, difference: -9)
    end
    assert_database_rejects do
      SellerReconciliationDiscrepancy.insert_all!([ {
        seller_reconciliation_id: -1,
        external_order_id: "orphan",
        issue_type: "amount_mismatch",
        expected_value: 10,
        paid_value: 9,
        difference: -1,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "schema uses a unique UUID public id and both durable foreign keys" do
    connection = ActiveRecord::Base.connection
    public_id_column = connection.columns(:seller_reconciliations).find do |column|
      column.name == "reconciliation_id"
    end
    public_id_index = connection.indexes(:seller_reconciliations).find do |index|
      index.columns == [ "reconciliation_id" ]
    end
    reconciliation_seller_fk = connection.foreign_keys(:seller_reconciliations).find do |foreign_key|
      foreign_key.to_table == "sellers"
    end
    discrepancy_reconciliation_fk = connection.foreign_keys(
      :seller_reconciliation_discrepancies
    ).find { |foreign_key| foreign_key.to_table == "seller_reconciliations" }

    assert_equal :uuid, public_id_column.type
    assert public_id_index&.unique
    assert reconciliation_seller_fk
    assert_equal :cascade, discrepancy_reconciliation_fk.on_delete

    reconciliation = create_reconciliation
    assert_database_rejects do
      SellerReconciliation.insert_all!([ {
        reconciliation_id: reconciliation.reconciliation_id,
        seller_id: @reconciliation_seller.id,
        start_date: Date.new(2018, 1, 1),
        end_date: Date.new(2018, 1, 31),
        status: "pending",
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  private

  def update_reconciliation(reconciliation, attributes)
    SellerReconciliation.where(id: reconciliation.id).update_all(attributes)
  end

  def insert_discrepancy(reconciliation, attributes)
    SellerReconciliationDiscrepancy.insert_all!([ {
      seller_reconciliation_id: reconciliation.id,
      issue_type: "amount_mismatch",
      expected_value: 10,
      paid_value: 9,
      difference: -1,
      created_at: Time.current,
      updated_at: Time.current
    }.merge(attributes) ])
  end

  def assert_database_rejects(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      SellerReconciliation.transaction(requires_new: true, &block)
    end
    @reconciliation_seller.reload
  end
end
