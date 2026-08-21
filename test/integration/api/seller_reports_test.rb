require "test_helper"
require_relative "../../support/method_replacement"

class Api::SellerReportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include MethodReplacement

  setup do
    clear_enqueued_jobs
    @seller = Seller.create!(
      seller_id: "report_seller_external_00000001",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
  end

  teardown do
    clear_enqueued_jobs
  end

  test "creates a pending report by external seller id and only enqueues its public id" do
    synchronous_generation = ->(*) { flunk "POST must not construct the CSV generator" }

    with_replaced_singleton_method(SellerPerformanceReportCsv, :new, synchronous_generation) do
      assert_enqueued_with(job: GenerateSellerPerformanceReportJob) do
        post "/api/sellers/#{@seller.seller_id}/reports",
          params: { start_date: "2018-01-01", end_date: "2018-06-30" },
          as: :json
      end
    end

    assert_response :accepted
    report = SellerPerformanceReport.find_by!(report_id: response.parsed_body.fetch("report_id"))
    assert_equal @seller, report.seller
    assert_equal Date.new(2018, 1, 1), report.start_date
    assert_equal Date.new(2018, 6, 30), report.end_date
    assert_equal "pending", report.status
    assert_nil report.csv_content
    assert_equal(
      {
        "report_id" => report.report_id,
        "seller_id" => @seller.seller_id,
        "status" => "pending"
      },
      response.parsed_body
    )
    assert_equal [ report.report_id ], enqueued_jobs.first.fetch(:args)
    refute_equal report.id.to_s, report.report_id
  end

  test "rejects missing malformed impossible reversed and non-scalar dates" do
    invalid_params = [
      {},
      { start_date: "2018-01-01" },
      { end_date: "2018-06-30" },
      { start_date: "01/01/2018", end_date: "2018-06-30" },
      { start_date: "2018-02-30", end_date: "2018-06-30" },
      { start_date: "2018-07-01", end_date: "2018-06-30" },
      { start_date: [ "2018-01-01" ], end_date: "2018-06-30" },
      { start_date: { value: "2018-01-01" }, end_date: "2018-06-30" },
      { start_date: "2018-01-01", end_date: [ "2018-06-30" ] }
    ]

    invalid_params.each do |params|
      assert_no_enqueued_jobs do
        post "/api/sellers/#{@seller.seller_id}/reports", params: params, as: :json
      end

      assert_response :unprocessable_content, "expected 422 for #{params.inspect}"
      assert_equal({ "error" => "invalid_dates" }, response.parsed_body)
    end
    assert_equal 0, SellerPerformanceReport.count
  end

  test "returns seller not found for an unknown external id and an internal id" do
    [ "unknown_seller", @seller.id.to_s ].each do |seller_id|
      assert_no_enqueued_jobs do
        post "/api/sellers/#{seller_id}/reports",
          params: { start_date: "2018-01-01", end_date: "2018-01-31" },
          as: :json
      end

      assert_response :not_found
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
    end
  end

  test "marks a persisted report failed when enqueueing fails without exposing the exception" do
    failure = ->(*) { raise "private queue credentials" }

    with_replaced_singleton_method(GenerateSellerPerformanceReportJob, :perform_later, failure) do
      post "/api/sellers/#{@seller.seller_id}/reports",
        params: { start_date: "2018-01-01", end_date: "2018-01-31" },
        as: :json
    end

    assert_response :service_unavailable
    assert_equal({ "error" => "report_enqueue_failed" }, response.parsed_body)
    refute_includes response.body, "private queue credentials"
    report = SellerPerformanceReport.order(:id).last
    assert_equal "failed", report.status
    assert_nil report.csv_content
  end

  test "status and download expose CSV only after completion" do
    report = create_report

    %w[pending processing failed].each do |status|
      report.update_columns(status: status, csv_content: nil)

      get "/api/reports/#{report.report_id}"
      assert_response :ok
      assert_equal(
        {
          "report_id" => report.report_id,
          "seller_id" => @seller.seller_id,
          "status" => status
        },
        response.parsed_body
      )

      get "/api/reports/#{report.report_id}/download"
      assert_response :conflict
      assert_equal({ "error" => "report_not_ready" }, response.parsed_body)
      refute_includes response.body, "month,orders"
    end

    csv = "month,orders\n2018-01,1\n"
    report.update_columns(status: "completed", csv_content: csv)

    get "/api/reports/#{report.report_id}"
    assert_response :ok
    assert_equal "/api/reports/#{report.report_id}/download", response.parsed_body.fetch("download_url")
    assert_equal %w[download_url report_id seller_id status], response.parsed_body.keys.sort

    get "/api/reports/#{report.report_id}/download"
    assert_response :ok
    assert_equal "text/csv", response.media_type
    assert_equal csv, response.body
    assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
    assert_match(report.report_id, response.headers.fetch("Content-Disposition"))
  end

  test "status and download require the public UUID and return the exact missing response" do
    report = create_report

    [ report.id.to_s, SecureRandom.uuid ].each do |identifier|
      get "/api/reports/#{identifier}"
      assert_response :not_found
      assert_equal({ "error" => "report_not_found" }, response.parsed_body)

      get "/api/reports/#{identifier}/download"
      assert_response :not_found
      assert_equal({ "error" => "report_not_found" }, response.parsed_body)
    end
  end

  private

  def create_report
    @seller.seller_performance_reports.create!(
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31)
    )
  end
end
