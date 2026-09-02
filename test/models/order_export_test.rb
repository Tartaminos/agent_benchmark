require "test_helper"

class OrderExportTest < ActiveSupport::TestCase
  test "assigns a public UUID and validates the filter and CSV lifecycle invariants" do
    export = OrderExport.create!(
      order_status: "delivered",
      delivery_status: "late",
      customer_state: "SP",
      purchase_from: Date.new(2018, 1, 1),
      purchase_to: Date.new(2018, 1, 31)
    )

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, export.export_id)
    refute_equal export.id.to_s, export.export_id
    assert_equal "pending", export.status

    export.assign_attributes(status: "unknown", csv_content: "partial")
    refute export.valid?
    assert export.errors.of_kind?(:status, :inclusion)
    assert export.errors.added?(:csv_content, "must be absent unless completed")

    export.assign_attributes(status: "completed", csv_content: nil)
    refute export.valid?
    assert export.errors.added?(:csv_content, "must be present when completed")
  end

  test "filter snapshot is immutable after creation" do
    export = OrderExport.create!(customer_state: "SP", purchase_from: Date.new(2018, 1, 1))

    assert_raises(ActiveRecord::ReadonlyAttributeError) { export.update!(customer_state: "RJ") }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { export.update!(purchase_from: Date.new(2018, 2, 1)) }
    assert_equal "SP", export.reload.customer_state
    assert_equal Date.new(2018, 1, 1), export.purchase_from
  end

  test "database constraints enforce lifecycle and ordered-range invariants" do
    export = OrderExport.create!

    assert_database_rejects { export.update_columns(status: "unknown") }
    assert_database_rejects { export.update_columns(status: "processing", csv_content: "partial") }
    assert_database_rejects { export.update_columns(status: "completed", csv_content: nil) }
    assert_database_rejects do
      OrderExport.connection.execute(
        "UPDATE order_exports SET purchase_from = DATE '2018-02-01', " \
          "purchase_to = DATE '2018-01-31' WHERE id = #{Integer(export.id)}"
      )
    end
  end

  test "schema guarantees unique public export identifiers" do
    export_id_index = ActiveRecord::Base.connection.indexes(:order_exports)
      .find { |index| index.columns == [ "export_id" ] }

    assert export_id_index&.unique
  end

  private

  def assert_database_rejects(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      OrderExport.transaction(requires_new: true, &block)
    end
  end
end
