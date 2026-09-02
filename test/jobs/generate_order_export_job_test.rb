require "test_helper"
require_relative "../support/method_replacement"

class GenerateOrderExportJobTest < ActiveJob::TestCase
  include MethodReplacement

  self.use_transactional_tests = false

  setup do
    OrderExport.delete_all
    @export = OrderExport.create!
  end

  teardown { OrderExport.delete_all }

  test "claims pending work before generation and atomically publishes the complete CSV" do
    generated_csv = "order_id,customer_id\nexternal-order,external-customer\n"
    generator = Object.new
    generator.define_singleton_method(:generate) do
      export = OrderExport.find_by!(export_id: @export_id)
      raise "export was not processing" unless export.status == "processing"
      raise "partial CSV was exposed" unless export.csv_content.nil?

      @generated_csv
    end
    generator.instance_variable_set(:@export_id, @export.export_id)
    generator.instance_variable_set(:@generated_csv, generated_csv)

    with_replaced_singleton_method(OrderExportCsv, :new, ->(*) { generator }) do
      GenerateOrderExportJob.perform_now(@export.export_id)
    end

    assert_equal "completed", @export.reload.status
    assert_equal generated_csv, @export.csv_content
  end

  test "duplicate executions cannot regenerate append to or corrupt completed output" do
    @export.update!(status: "completed", csv_content: "original csv")
    calls = 0
    factory = lambda do |*|
      calls += 1
      raise "generator must not be called"
    end

    with_replaced_singleton_method(OrderExportCsv, :new, factory) do
      2.times { GenerateOrderExportJob.perform_now(@export.export_id) }
    end

    assert_equal 0, calls
    assert_equal "completed", @export.reload.status
    assert_equal "original csv", @export.csv_content
  end

  test "concurrent executions allow only one generator to claim and publish the export" do
    entered_generation = Queue.new
    release_generation = Queue.new
    calls = 0
    calls_lock = Mutex.new
    generated_csv = "order_id,customer_id\nexternal-order,external-customer\n"
    generator = Object.new
    generator.define_singleton_method(:generate) do
      entered_generation << true
      release_generation.pop
      generated_csv
    end
    factory = lambda do |*|
      calls_lock.synchronize { calls += 1 }
      generator
    end

    with_replaced_singleton_method(OrderExportCsv, :new, factory) do
      claimant = Thread.new { GenerateOrderExportJob.perform_now(@export.export_id) }
      entered_generation.pop
      duplicate = Thread.new { GenerateOrderExportJob.perform_now(@export.export_id) }
      duplicate.join
      release_generation << true
      claimant.join
    end

    assert_equal 1, calls
    assert_equal "completed", @export.reload.status
    assert_equal generated_csv, @export.csv_content
  end

  test "generation failure records failed without partial CSV and re-raises" do
    generator = Object.new
    generator.define_singleton_method(:generate) { raise "private generation detail" }

    error = assert_raises(RuntimeError) do
      with_replaced_singleton_method(OrderExportCsv, :new, ->(*) { generator }) do
        GenerateOrderExportJob.perform_now(@export.export_id)
      end
    end

    assert_equal "private generation detail", error.message
    assert_equal "failed", @export.reload.status
    assert_nil @export.csv_content
  end

  test "missing and non-pending exports are harmless no-ops" do
    @export.update_columns(status: "failed", csv_content: nil)
    calls = 0

    with_replaced_singleton_method(OrderExportCsv, :new, ->(*) { calls += 1 }) do
      GenerateOrderExportJob.perform_now(@export.export_id)
      GenerateOrderExportJob.perform_now(SecureRandom.uuid)
    end

    assert_equal 0, calls
    assert_equal "failed", @export.reload.status
  end
end
