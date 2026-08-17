require "test_helper"

class Api::SellerReportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  self.fixture_table_names = []

  setup do
    @seller = Seller.create!(
      seller_id: "report_seller_external",
      zip_code_prefix: "01001",
      city: "sao paulo",
      state: "SP"
    )
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
  end

  test "create validates the external seller, persists a public pending report, and only enqueues generation" do
    assert_difference -> { SellerPerformanceReport.count }, 1 do
      assert_enqueued_with(job: GenerateSellerPerformanceReportJob) do
        post "/api/sellers/#{@seller.seller_id}/reports",
             params: { start_date: "2018-01-01", end_date: "2018-06-30" },
             as: :json
      end
    end

    assert_response :accepted
    report = SellerPerformanceReport.order(:id).last
    assert_equal "pending", report.status
    assert_nil report.csv_content
    assert_equal [ report.id ], enqueued_jobs.last.fetch(:args)
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
                 report.public_id)
    assert_equal(
      {
        "report_id" => report.public_id,
        "seller_id" => @seller.seller_id,
        "status" => "pending"
      },
      response.parsed_body
    )
    refute_equal report.id.to_s, response.parsed_body.fetch("report_id")
  end

  test "create rejects missing malformed structured and reversed dates without persisting or enqueueing" do
    invalid_ranges = [
      {},
      { start_date: "2018-01-01" },
      { end_date: "2018-01-31" },
      { start_date: "2018-02-30", end_date: "2018-03-01" },
      { start_date: "2018-1-01", end_date: "2018-01-31" },
      { start_date: [ "2018-01-01" ], end_date: "2018-01-31" },
      { start_date: { value: "2018-01-01" }, end_date: "2018-01-31" },
      { start_date: "2018-02-01", end_date: "2018-01-31" }
    ]

    invalid_ranges.each do |params|
      assert_no_difference -> { SellerPerformanceReport.count } do
        assert_no_enqueued_jobs do
          post "/api/sellers/#{@seller.seller_id}/reports", params: params, as: :json
        end
      end

      assert_response :unprocessable_content, "expected #{params.inspect} to be rejected"
      assert_equal({ "error" => "invalid_date_range" }, response.parsed_body)
    end
  end

  test "create returns the specified not-found contract and does not accept an internal seller id" do
    [ "does-not-exist", @seller.id.to_s ].each do |seller_id|
      assert_no_difference -> { SellerPerformanceReport.count } do
        assert_no_enqueued_jobs do
          post "/api/sellers/#{seller_id}/reports",
               params: { start_date: "2018-01-01", end_date: "2018-01-31" },
               as: :json
        end
      end

      assert_response :not_found
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
    end
  end

  test "status exposes only the public contract for every lifecycle state" do
    %w[pending processing failed completed].each do |status|
      report = create_report(status: status, csv_content: status == "completed" ? "month,orders\n" : nil)

      get "/api/reports/#{report.public_id}"

      assert_response :success
      expected = {
        "report_id" => report.public_id,
        "seller_id" => @seller.seller_id,
        "status" => status,
        "start_date" => "2018-01-01",
        "end_date" => "2018-01-31"
      }
      expected["download_url"] = "/api/reports/#{report.public_id}/download" if status == "completed"
      assert_equal expected, response.parsed_body
    end
  end

  test "download returns complete CSV and refuses every incomplete state without partial content" do
    completed = create_report(status: "completed", csv_content: "month,orders\n2018-01,1\n")

    get "/api/reports/#{completed.public_id}/download"

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_equal completed.csv_content, response.body

    %w[pending processing failed].each do |status|
      report = create_report(status: status)

      get "/api/reports/#{report.public_id}/download"

      assert_response :conflict
      assert_equal "application/json", response.media_type
      assert_equal({ "error" => "report_not_ready" }, response.parsed_body)
      refute_includes response.body, "month,orders"
    end
  end

  test "status and download use only the public UUID" do
    report = create_report

    get "/api/reports/#{report.id}"
    assert_response :not_found
    assert_equal({ "error" => "report_not_found" }, response.parsed_body)

    get "/api/reports/#{report.id}/download"
    assert_response :not_found
    assert_equal({ "error" => "report_not_found" }, response.parsed_body)
  end

  private

  def create_report(status: "pending", csv_content: nil)
    SellerPerformanceReport.create!(
      seller: @seller,
      start_date: Date.new(2018, 1, 1),
      end_date: Date.new(2018, 1, 31),
      status: status,
      csv_content: csv_content
    )
  end
end
