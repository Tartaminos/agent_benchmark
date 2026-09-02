require "test_helper"
require_relative "../support/method_replacement"
require_relative "../support/reconciliation_test_data"

class ProcessSellerReconciliationJobTest < ActiveJob::TestCase
  include MethodReplacement
  include ReconciliationTestData

  self.use_transactional_tests = false

  setup do
    build_reconciliation_data
    @created_seller_ids = [ @reconciliation_seller.id, @other_reconciliation_seller.id ]
    @created_customer_id = @reconciliation_customer.id
  end

  teardown do
    SellerReconciliation.where(seller_id: @created_seller_ids).delete_all
    Seller.where(id: @created_seller_ids).delete_all
    Customer.where(id: @created_customer_id).delete_all
  end

  test "claims pending work and publishes an empty completed snapshot through the processor" do
    reconciliation = create_reconciliation

    ProcessSellerReconciliationJob.perform_now(reconciliation.reconciliation_id)

    reconciliation.reload
    assert_equal "completed", reconciliation.status
    assert_nil reconciliation.processing_token
    assert_equal 0, reconciliation.orders_checked
  end

  test "completed and processing duplicate deliveries are harmless no-ops" do
    completed = complete_reconciliation(create_reconciliation)
    processing = create_reconciliation(status: "processing", processing_token: SecureRandom.uuid)
    calls = 0

    with_replaced_singleton_method(SellerReconciliationProcessor, :new, ->(*) { calls += 1 }) do
      2.times { ProcessSellerReconciliationJob.perform_now(completed.reconciliation_id) }
      ProcessSellerReconciliationJob.perform_now(processing.reconciliation_id)
      ProcessSellerReconciliationJob.perform_now(SecureRandom.uuid)
    end

    assert_equal 0, calls
    assert_equal "completed", completed.reload.status
    assert_equal "processing", processing.reload.status
  end

  test "failed work is retryable" do
    reconciliation = create_reconciliation(status: "failed")

    ProcessSellerReconciliationJob.perform_now(reconciliation.reconciliation_id)

    assert_equal "completed", reconciliation.reload.status
    assert_equal 0, reconciliation.orders_checked
  end

  test "processing failure removes partial rows marks failed and re-raises" do
    reconciliation = create_reconciliation
    processor = Object.new
    processor.define_singleton_method(:process) do
      current = SellerReconciliation.find(@reconciliation_id)
      raise "not claimed" unless current.status == "processing" && current.processing_token.present?
      current.discrepancies.create!(
        external_order_id: "partial_external_order",
        issue_type: "amount_mismatch",
        expected_value: 10,
        paid_value: 9,
        difference: -1
      )
      raise "private database detail"
    end
    processor.instance_variable_set(:@reconciliation_id, reconciliation.id)

    error = assert_raises(RuntimeError) do
      with_replaced_singleton_method(SellerReconciliationProcessor, :new, ->(*) { processor }) do
        ProcessSellerReconciliationJob.perform_now(reconciliation.reconciliation_id)
      end
    end

    assert_equal "private database detail", error.message
    reconciliation.reload
    assert_equal "failed", reconciliation.status
    assert_nil reconciliation.processing_token
    assert_empty reconciliation.discrepancies
    SellerReconciliation::SUMMARY_ATTRIBUTES.each { |attribute| assert_nil reconciliation.public_send(attribute) }
  end

  test "a stale failing attempt cannot fail or clean a newer token owner" do
    reconciliation = create_reconciliation
    newer_token = SecureRandom.uuid
    processor = Object.new
    processor.define_singleton_method(:process) do
      current = SellerReconciliation.find(@reconciliation_id)
      current.update_columns(processing_token: @newer_token)
      current.discrepancies.create!(
        external_order_id: "new_owner_partial",
        issue_type: "amount_mismatch",
        expected_value: 10,
        paid_value: 9,
        difference: -1
      )
      raise "stale worker failed"
    end
    processor.instance_variable_set(:@reconciliation_id, reconciliation.id)
    processor.instance_variable_set(:@newer_token, newer_token)

    assert_raises(RuntimeError) do
      with_replaced_singleton_method(SellerReconciliationProcessor, :new, ->(*) { processor }) do
        ProcessSellerReconciliationJob.perform_now(reconciliation.reconciliation_id)
      end
    end

    reconciliation.reload
    assert_equal "processing", reconciliation.status
    assert_equal newer_token, reconciliation.processing_token
    assert_equal [ "new_owner_partial" ], reconciliation.discrepancies.pluck(:external_order_id)
  end

  test "concurrent deliveries allow only one token owner to process" do
    reconciliation = create_reconciliation
    entered_processing = Queue.new
    release_processing = Queue.new
    calls = 0
    calls_lock = Mutex.new
    factory = lambda do |reconciliation_id:, processing_token:|
      calls_lock.synchronize { calls += 1 }
      processor = Object.new
      processor.define_singleton_method(:process) do
        entered_processing << true
        release_processing.pop
        SellerReconciliation.find(reconciliation_id).update!(
          status: "completed",
          processing_token: nil,
          orders_checked: 0,
          matched_orders: 0,
          inconsistent_orders: 0,
          missing_payment_orders: 0,
          amount_mismatch_orders: 0,
          expected_value: 0,
          paid_value: 0,
          difference: 0
        )
      end
      processor
    end

    with_replaced_singleton_method(SellerReconciliationProcessor, :new, factory) do
      claimant = Thread.new { ProcessSellerReconciliationJob.perform_now(reconciliation.reconciliation_id) }
      entered_processing.pop
      duplicate = Thread.new { ProcessSellerReconciliationJob.perform_now(reconciliation.reconciliation_id) }
      duplicate.value
      release_processing << true
      claimant.value
    end

    assert_equal 1, calls
    assert_equal "completed", reconciliation.reload.status
    assert_nil reconciliation.processing_token
  end
end
