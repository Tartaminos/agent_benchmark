require "test_helper"

class SellerPerformanceReportTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    seller = Seller.create!(
      seller_id: "constraint-seller",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @report = SellerPerformanceReport.create!(
      seller: seller,
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31)
    )
  end

  test "database constraints preserve lifecycle date and complete-CSV invariants" do
    assert_database_rejects { @report.update_columns(status: "unknown") }
    assert_database_rejects { @report.update_columns(start_date: Date.new(2018, 2, 1)) }
    assert_database_rejects { @report.update_columns(status: "completed", csv_data: nil) }
    assert_database_rejects { @report.update_columns(csv_data: "partial") }

    assert_equal "pending", @report.reload.status
    assert_nil @report.csv_data
    assert_equal Date.new(2018, 1, 1), @report.start_date
  end

  private

  def assert_database_rejects(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      SellerPerformanceReport.transaction(requires_new: true, &block)
    end
  end
end
