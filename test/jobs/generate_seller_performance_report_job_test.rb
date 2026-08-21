require "test_helper"
require_relative "../support/method_replacement"

class GenerateSellerPerformanceReportJobTest < ActiveJob::TestCase
  include MethodReplacement
  setup do
    @seller = Seller.create!(
      seller_id: "job_report_seller_0000000000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    @report = @seller.seller_performance_reports.create!(
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31)
    )
  end

  test "claims pending work before generation and completes only with the generated CSV" do
    generated_csv = "month,orders\n2018-01,1\n"
    generator = Object.new
    generator.define_singleton_method(:generate) do
      report = SellerPerformanceReport.find_by!(report_id: @report_id)
      raise "report was not processing" unless report.status == "processing"
      raise "partial CSV was exposed" unless report.csv_content.nil?

      generated_csv
    end
    generator.instance_variable_set(:@report_id, @report.report_id)

    with_replaced_singleton_method(SellerPerformanceReportCsv, :new, ->(*) { generator }) do
      GenerateSellerPerformanceReportJob.perform_now(@report.report_id)
    end

    @report.reload
    assert_equal "completed", @report.status
    assert_equal generated_csv, @report.csv_content
  end

  test "duplicate execution does not regenerate an already completed report" do
    @report.update!(status: "completed", csv_content: "original csv")
    calls = 0
    factory = lambda do |*|
      calls += 1
      raise "generator must not be called"
    end

    with_replaced_singleton_method(SellerPerformanceReportCsv, :new, factory) do
      2.times { GenerateSellerPerformanceReportJob.perform_now(@report.report_id) }
    end

    assert_equal 0, calls
    assert_equal "completed", @report.reload.status
    assert_equal "original csv", @report.csv_content
  end

  test "generation failure records failed without CSV and re-raises for job infrastructure" do
    generator = Object.new
    generator.define_singleton_method(:generate) { raise "private provider detail" }

    error = assert_raises(RuntimeError) do
      with_replaced_singleton_method(SellerPerformanceReportCsv, :new, ->(*) { generator }) do
        GenerateSellerPerformanceReportJob.perform_now(@report.report_id)
      end
    end

    assert_equal "private provider detail", error.message
    assert_equal "failed", @report.reload.status
    assert_nil @report.csv_content
  end

  test "a missing public report id is a harmless no-op" do
    assert_nothing_raised do
      GenerateSellerPerformanceReportJob.perform_now(SecureRandom.uuid)
    end
  end
end
