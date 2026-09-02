require "test_helper"
require_relative "../../support/method_replacement"

class Api::OrderExportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include MethodReplacement

  setup { clear_enqueued_jobs }
  teardown { clear_enqueued_jobs }

  test "creates an immutable pending export and enqueues only its public id without generating inline" do
    synchronous_generation = ->(*) { flunk "POST must not construct the CSV generator" }

    with_replaced_singleton_method(OrderExportCsv, :new, synchronous_generation) do
      assert_enqueued_with(job: GenerateOrderExportJob) do
        post "/api/order_exports", params: {
          order_status: "delivered",
          delivery_status: "late",
          customer_state: "SP",
          purchase_from: "2018-01-01",
          purchase_to: "2018-06-30"
        }, as: :json
      end
    end

    assert_response :accepted
    export = OrderExport.find_by!(export_id: response.parsed_body.fetch("export_id"))
    assert_equal "pending", export.status
    assert_nil export.csv_content
    assert_equal "delivered", export.order_status
    assert_equal "late", export.delivery_status
    assert_equal "SP", export.customer_state
    assert_equal Date.new(2018, 1, 1), export.purchase_from
    assert_equal Date.new(2018, 6, 30), export.purchase_to
    assert_equal({ "export_id" => export.export_id, "status" => "pending" }, response.parsed_body)
    assert_equal [ export.export_id ], enqueued_jobs.first.fetch(:args)
    refute_equal export.id.to_s, export.export_id
  end

  test "rejects every invalid filter class without persisting or enqueueing" do
    invalid_params = [
      { order_status: "returned" },
      { delivery_status: "overdue" },
      { customer_state: "XX" },
      { purchase_from: "2018-1-01" },
      { purchase_from: "2018-02-30" },
      { purchase_to: "01/31/2018" },
      { purchase_from: "2018-02-01", purchase_to: "2018-01-31" },
      { order_status: [ "delivered" ] },
      { customer_state: { value: "SP" } },
      { purchase_to: 20180131 }
    ]

    invalid_params.each do |params|
      assert_no_enqueued_jobs do
        assert_no_difference -> { OrderExport.count } do
          post "/api/order_exports", params: params, as: :json
        end
      end

      assert_response :unprocessable_content, "expected 422 for #{params.inspect}"
      assert_equal "invalid_filters", response.parsed_body.fetch("error")
    end
  end

  test "status and download expose the exact CSV only after completion" do
    export = OrderExport.create!

    %w[pending processing failed].each do |status|
      export.update_columns(status: status, csv_content: nil)

      get "/api/order_exports/#{export.export_id}"
      assert_response :ok
      assert_equal({ "export_id" => export.export_id, "status" => status }, response.parsed_body)

      get "/api/order_exports/#{export.export_id}/download"
      assert_response :conflict
      assert_equal({ "error" => "export_not_ready" }, response.parsed_body)
      refute_includes response.body, "order_id,customer_id"
    end

    csv = "order_id,customer_id\nexternal-order,external-customer\n"
    export.update_columns(status: "completed", csv_content: csv)

    get "/api/order_exports/#{export.export_id}"
    assert_response :ok
    assert_equal "/api/order_exports/#{export.export_id}/download", response.parsed_body.fetch("download_url")
    assert_equal %w[download_url export_id status], response.parsed_body.keys.sort

    get "/api/order_exports/#{export.export_id}/download"
    assert_response :ok
    assert_equal "text/csv", response.media_type
    assert_equal csv, response.body
    assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
    assert_match(export.export_id, response.headers.fetch("Content-Disposition"))
  end

  test "internal and unknown identifiers are not valid public identifiers" do
    export = OrderExport.create!

    [ export.id.to_s, SecureRandom.uuid ].each do |identifier|
      get "/api/order_exports/#{identifier}"
      assert_response :not_found
      assert_equal({ "error" => "export_not_found" }, response.parsed_body)

      get "/api/order_exports/#{identifier}/download"
      assert_response :not_found
      assert_equal({ "error" => "export_not_found" }, response.parsed_body)
    end
  end

  test "enqueue failure leaves a queryable failed export without leaking details" do
    failure = ->(*) { raise "private queue credentials" }

    with_replaced_singleton_method(GenerateOrderExportJob, :perform_later, failure) do
      post "/api/order_exports", params: { customer_state: "SP" }, as: :json
    end

    assert_response :service_unavailable
    assert_equal({ "error" => "export_enqueue_failed" }, response.parsed_body)
    refute_includes response.body, "private queue credentials"
    export = OrderExport.order(:id).last
    assert_equal "failed", export.status
    assert_nil export.csv_content

    get "/api/order_exports/#{export.export_id}"
    assert_response :ok
    assert_equal "failed", response.parsed_body.fetch("status")
  end
end
