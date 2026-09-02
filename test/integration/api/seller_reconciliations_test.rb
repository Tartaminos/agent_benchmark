require "test_helper"
require_relative "../../support/method_replacement"
require_relative "../../support/reconciliation_test_data"

class Api::SellerReconciliationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include MethodReplacement
  include ReconciliationTestData

  setup do
    clear_enqueued_jobs
    build_reconciliation_data
  end

  teardown { clear_enqueued_jobs }

  test "creates pending work by external seller id and enqueues only its public UUID" do
    inline_processor = ->(*) { flunk "POST must not construct the reconciliation processor" }
    with_replaced_singleton_method(SellerReconciliationProcessor, :new, inline_processor) do
      assert_enqueued_with(job: ProcessSellerReconciliationJob) do
        post "/api/sellers/#{@reconciliation_seller.seller_id}/reconciliations",
          params: { start_date: "2018-01-01", end_date: "2018-01-31" }, as: :json
      end
    end

    assert_response :accepted
    body = response.parsed_body
    reconciliation = SellerReconciliation.find_by!(reconciliation_id: body.fetch("reconciliation_id"))
    assert_equal @reconciliation_seller, reconciliation.seller
    assert_equal "pending", reconciliation.status
    assert_equal Date.new(2018, 1, 1), reconciliation.start_date
    assert_equal Date.new(2018, 1, 31), reconciliation.end_date
    assert_equal [ reconciliation.reconciliation_id ], enqueued_jobs.first.fetch(:args)
    refute_equal reconciliation.id.to_s, reconciliation.reconciliation_id
    assert_equal(
      {
        "reconciliation_id" => reconciliation.reconciliation_id,
        "seller_id" => @reconciliation_seller.seller_id,
        "status" => "pending",
        "start_date" => "2018-01-01",
        "end_date" => "2018-01-31"
      }, body
    )
  end

  test "rejects missing malformed impossible reversed and structured dates before seller lookup" do
    invalid_params = [
      {},
      { start_date: "2018-01-01" },
      { end_date: "2018-01-31" },
      { start_date: "2018-1-01", end_date: "2018-01-31" },
      { start_date: "2018-02-30", end_date: "2018-03-01" },
      { start_date: "2018-02-01", end_date: "2018-01-31" },
      { start_date: [ "2018-01-01" ], end_date: "2018-01-31" },
      { start_date: { value: "2018-01-01" }, end_date: "2018-01-31" },
      { start_date: "2018-01-01", end_date: 20180131 }
    ]

    invalid_params.each do |params|
      assert_no_enqueued_jobs do
        assert_no_difference -> { SellerReconciliation.count } do
          post "/api/sellers/unknown/reconciliations", params: params, as: :json
        end
      end
      assert_response :unprocessable_content, "expected 422 for #{params.inspect}"
      assert_equal({ "error" => "invalid_dates" }, response.parsed_body)
    end
  end

  test "rejects unknown and internal seller ids without enqueueing" do
    [ "unknown", @reconciliation_seller.id.to_s ].each do |seller_id|
      assert_no_enqueued_jobs do
        post "/api/sellers/#{seller_id}/reconciliations",
          params: { start_date: "2018-01-01", end_date: "2018-01-31" }, as: :json
      end
      assert_response :not_found
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
    end
  end

  test "enqueue failure persists queryable failed state without leaking details" do
    failure = ->(*) { raise "private queue credentials" }

    with_replaced_singleton_method(ProcessSellerReconciliationJob, :perform_later, failure) do
      post "/api/sellers/#{@reconciliation_seller.seller_id}/reconciliations",
        params: { start_date: "2018-01-01", end_date: "2018-01-31" }, as: :json
    end

    assert_response :service_unavailable
    assert_equal({ "error" => "reconciliation_enqueue_failed" }, response.parsed_body)
    refute_includes response.body, "private queue credentials"
    reconciliation = SellerReconciliation.order(:id).last
    assert_equal "failed", reconciliation.status

    get "/api/reconciliations/#{reconciliation.reconciliation_id}"
    assert_response :ok
    assert_equal "failed", response.parsed_body.fetch("status")
    refute response.parsed_body.key?("summary")
  end

  test "status exposes final summary only when completed and accepts only public ids" do
    reconciliation = create_reconciliation

    %w[pending processing failed].each do |status|
      token = status == "processing" ? SecureRandom.uuid : nil
      reconciliation.update_columns(status: status, processing_token: token)
      get "/api/reconciliations/#{reconciliation.reconciliation_id}"
      assert_response :ok
      assert_equal status, response.parsed_body.fetch("status")
      refute response.parsed_body.key?("summary")
    end

    complete_reconciliation(reconciliation, orders_checked: 2, matched_orders: 1,
      inconsistent_orders: 1, missing_payment_orders: 0, amount_mismatch_orders: 1,
      expected_value: "10.10", paid_value: "9.00", difference: "-1.10")
    get "/api/reconciliations/#{reconciliation.reconciliation_id}"
    assert_response :ok
    body = response.parsed_body
    assert_equal %w[end_date reconciliation_id seller_id start_date status summary], body.keys.sort
    assert_equal(
      {
        "orders_checked" => 2,
        "matched_orders" => 1,
        "inconsistent_orders" => 1,
        "missing_payment_orders" => 0,
        "amount_mismatch_orders" => 1,
        "expected_value" => "10.10",
        "paid_value" => "9.00",
        "difference" => "-1.10",
        "discrepancies_url" => "/api/reconciliations/#{reconciliation.reconciliation_id}/discrepancies"
      }, body.fetch("summary")
    )

    [ reconciliation.id.to_s, SecureRandom.uuid ].each do |identifier|
      get "/api/reconciliations/#{identifier}"
      assert_response :not_found
      assert_equal({ "error" => "reconciliation_not_found" }, response.parsed_body)
    end
  end

  test "completed discrepancies are ordered and database paginated with defaults and empty out-of-range pages" do
    reconciliation = complete_reconciliation(create_reconciliation)
    27.times do |index|
      create_discrepancy(reconciliation, order_id: format("order_%02d", 26 - index))
    end

    sql = capture_sql do
      get "/api/reconciliations/#{reconciliation.reconciliation_id}/discrepancies"
    end
    assert_response :ok
    body = response.parsed_body
    assert_equal 1, body.fetch("page")
    assert_equal 25, body.fetch("per_page")
    assert_equal 27, body.fetch("total_count")
    assert_equal 2, body.fetch("total_pages")
    assert_equal((0..24).map { |index| format("order_%02d", index) },
      body.fetch("discrepancies").map { |row| row.fetch("order_id") })
    assert_equal %w[difference expected_value issue_type order_id paid_value],
      body.fetch("discrepancies").first.keys.sort
    assert_equal [ "10.00", "9.00", "-1.00" ], body.fetch("discrepancies").first.values_at(
      "expected_value", "paid_value", "difference"
    )
    page_query = sql.find do |statement|
      statement.match?(/SELECT .*seller_reconciliation_discrepancies/i) && statement.match?(/LIMIT/i)
    end
    assert page_query, "expected discrepancy rows to be limited in the database"
    assert_match(/ORDER BY .*external_order_id/i, page_query)

    get "/api/reconciliations/#{reconciliation.reconciliation_id}/discrepancies",
      params: { page: "2", per_page: "25" }
    assert_equal %w[order_25 order_26],
      response.parsed_body.fetch("discrepancies").map { |row| row.fetch("order_id") }

    get "/api/reconciliations/#{reconciliation.reconciliation_id}/discrepancies",
      params: { page: "999", per_page: "100" }
    assert_response :ok
    assert_empty response.parsed_body.fetch("discrepancies")
  end

  test "pagination rejects malformed scalar structured nonpositive and oversized values" do
    reconciliation = complete_reconciliation(create_reconciliation)
    invalid_params = [
      { page: "0" }, { page: "-1" }, { page: "1.5" }, { page: " 1" },
      { per_page: "0" }, { per_page: "101" }, { per_page: [ "25" ] },
      { page: { value: "1" } }
    ]

    invalid_params.each do |params|
      get "/api/reconciliations/#{reconciliation.reconciliation_id}/discrepancies", params: params
      assert_response :unprocessable_content, "expected 422 for #{params.inspect}"
      assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
    end
  end

  test "incomplete and unknown reconciliations never expose discrepancy rows" do
    reconciliation = create_reconciliation
    create_discrepancy(reconciliation, order_id: "partial_external_order")

    get "/api/reconciliations/#{reconciliation.reconciliation_id}/discrepancies"
    assert_response :conflict
    assert_equal({ "error" => "reconciliation_not_ready" }, response.parsed_body)
    refute_includes response.body, "partial_external_order"

    [ reconciliation.id.to_s, SecureRandom.uuid ].each do |identifier|
      get "/api/reconciliations/#{identifier}/discrepancies"
      assert_response :not_found
      assert_equal({ "error" => "reconciliation_not_found" }, response.parsed_body)
    end
  end

  private

  def capture_sql
    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] unless payload[:name] == "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    statements
  end
end
