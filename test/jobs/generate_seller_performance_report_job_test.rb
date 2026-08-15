require "test_helper"

class GenerateSellerPerformanceReportJobTest < ActiveJob::TestCase
  self.fixture_table_names = []

  setup do
    @seller = Seller.create!(
      seller_id: "job-seller",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  test "claims a pending report before generation and completes only with the full CSV" do
    report = create_report
    generated_csv = "month,orders\n2018-01,1\n"
    generator = Object.new
    generator.define_singleton_method(:generate) do
      raise "report was not processing while CSV was generated" unless report.reload.status == "processing"

      generated_csv
    end

    with_class_method_stub(SellerPerformanceReportCsv, :new, ->(*) { generator }) do
      GenerateSellerPerformanceReportJob.perform_now(report.public_id)
    end

    assert_equal "completed", report.reload.status
    assert_equal generated_csv, report.csv_data
  end

  test "does not regenerate reports that are no longer pending" do
    %w[processing failed completed].each do |status|
      report = create_report(status: status, csv_data: ("existing CSV" if status == "completed"))

      with_class_method_stub(
        SellerPerformanceReportCsv,
        :new,
        ->(*) { flunk "duplicate execution generated CSV for #{status}" }
      ) do
        GenerateSellerPerformanceReportJob.perform_now(report.public_id)
      end

      assert_equal status, report.reload.status
      assert_equal("existing CSV", report.csv_data) if status == "completed"
    end

    assert_nothing_raised do
      GenerateSellerPerformanceReportJob.perform_now(SecureRandom.uuid)
    end
  end

  test "marks a claimed report failed clears CSV state and reraises without storing exception details" do
    report = create_report
    generator = Object.new
    generator.define_singleton_method(:generate) do
      report.update_column(:updated_at, Time.current)
      raise "private database credentials"
    end

    error = assert_raises(RuntimeError) do
      with_class_method_stub(SellerPerformanceReportCsv, :new, ->(*) { generator }) do
        GenerateSellerPerformanceReportJob.perform_now(report.public_id)
      end
    end

    assert_equal "private database credentials", error.message
    assert_equal "failed", report.reload.status
    assert_nil report.csv_data
    refute_includes report.attributes.values.compact.map(&:to_s).join(" "), "private database credentials"
  end

  private

  def create_report(status: "pending", csv_data: nil)
    SellerPerformanceReport.create!(
      seller: @seller,
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31),
      status: status,
      csv_data: csv_data
    )
  end


  def with_class_method_stub(receiver, method_name, replacement)
    singleton_class = receiver.singleton_class
    originally_defined = singleton_class.instance_methods(false).include?(method_name)
    original_method = receiver.method(method_name) if originally_defined
    singleton_class.define_method(method_name) do |*args, **kwargs, &block|
      replacement.call(*args, **kwargs, &block)
    end
    yield
  ensure
    singleton_class.remove_method(method_name)
    singleton_class.define_method(method_name, original_method) if originally_defined
  end
end
