require "test_helper"

class SellerPerformanceReportTest < ActiveSupport::TestCase
  setup do
    @seller = Seller.create!(
      seller_id: "model_report_seller_00000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  test "assigns a unique public UUID and validates dates status and CSV lifecycle" do
    report = @seller.seller_performance_reports.create!(
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31)
    )

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, report.report_id)
    assert_equal "pending", report.status
    refute_equal report.id.to_s, report.report_id

    report.assign_attributes(start_date: nil, end_date: nil, status: "unknown")
    refute report.valid?
    assert report.errors.of_kind?(:start_date, :blank)
    assert report.errors.of_kind?(:end_date, :blank)
    assert report.errors.of_kind?(:status, :inclusion)

    report.assign_attributes(
      start_date: Date.new(2018, 2, 1),
      end_date: Date.new(2018, 1, 31),
      status: "processing",
      csv_content: "partial"
    )
    refute report.valid?
    assert report.errors.added?(:end_date, "must be on or after start_date")
    assert report.errors.added?(:csv_content, "must be absent unless completed")

    report.assign_attributes(
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31),
      status: "completed",
      csv_content: nil
    )
    refute report.valid?
    assert report.errors.added?(:csv_content, "must be present when completed")
  end

  test "database constraints enforce status date range and completed CSV invariants" do
    report = @seller.seller_performance_reports.create!(
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31)
    )

    assert_database_rejects { report.update_columns(status: "unknown") }
    assert_database_rejects { report.update_columns(start_date: Date.new(2018, 2, 1)) }
    assert_database_rejects { report.update_columns(status: "processing", csv_content: "partial") }
    assert_database_rejects { report.update_columns(status: "completed", csv_content: nil) }
  end

  test "schema has unique public report ids and the seller-order aggregation index" do
    report_indexes = ActiveRecord::Base.connection.indexes(:seller_performance_reports)
    report_id_index = report_indexes.find { |index| index.columns == [ "report_id" ] }
    assert report_id_index&.unique

    item_indexes = ActiveRecord::Base.connection.indexes(:order_items)
    assert item_indexes.any? { |index| index.columns == %w[seller_id order_id] }
  end

  private

  def assert_database_rejects(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      SellerPerformanceReport.transaction(requires_new: true, &block)
    end
    @seller.reload
  end
end
