require "test_helper"
require "active_job/test_helper"

module Api
  class SellerPerformanceReportsTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    self.fixture_table_names = []

    setup do
      clear_enqueued_jobs
      @seller = create_seller("external-seller-123")
    end

    teardown { clear_enqueued_jobs }

    test "creates a public pending report and only enqueues its generation" do
      with_class_method_stub(
        SellerPerformanceReportCsv,
        :new,
        ->(*) { raise "CSV generation ran in the request" }
      ) do
        assert_enqueued_jobs 1, only: GenerateSellerPerformanceReportJob do
          post "/api/sellers/#{@seller.seller_id}/reports",
            params: { start_date: "2018-01-01", end_date: "2018-06-30" }
        end
      end

      assert_response :accepted
      assert_equal "application/json", response.media_type
      assert_equal %w[report_id seller_id status], response.parsed_body.keys.sort
      assert_equal @seller.seller_id, response.parsed_body["seller_id"]
      assert_equal "pending", response.parsed_body["status"]
      assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
        response.parsed_body["report_id"])

      report = SellerPerformanceReport.find_by!(public_id: response.parsed_body.fetch("report_id"))
      assert_equal Date.new(2018, 1, 1), report.start_date
      assert_equal Date.new(2018, 6, 30), report.end_date
      assert_equal [ report.public_id ], enqueued_jobs.fetch(0).fetch(:args)
      refute_equal report.id.to_s, response.parsed_body["report_id"]
    end

    test "accepts a tokenless JSON report request when forgery protection is enabled" do
      original_forgery_setting = ActionController::Base.allow_forgery_protection
      begin
        ActionController::Base.allow_forgery_protection = true

        assert ActionController::Base.allow_forgery_protection,
          "the request must exercise enabled global forgery protection"
        assert_enqueued_jobs 1, only: GenerateSellerPerformanceReportJob do
          post "/api/sellers/#{@seller.seller_id}/reports",
            params: { start_date: "2018-01-01", end_date: "2018-01-31" }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
        end

        assert_response :accepted
        assert_equal "pending", response.parsed_body["status"]
        assert_equal 1, SellerPerformanceReport.where(seller: @seller).count
      ensure
        ActionController::Base.allow_forgery_protection = original_forgery_setting
      end

      assert_equal original_forgery_setting, ActionController::Base.allow_forgery_protection
    end

    test "rejects missing invalid noncanonical structured and reversed dates before seller lookup" do
      invalid_ranges = [
        { end_date: "2018-06-30" },
        { start_date: "2018-01-01" },
        { start_date: "not-a-date", end_date: "2018-06-30" },
        { start_date: "2018-02-29", end_date: "2018-06-30" },
        { start_date: "2018-1-01", end_date: "2018-06-30" },
        { start_date: "2018-01-01 ", end_date: "2018-06-30" },
        { start_date: [ "2018-01-01" ], end_date: "2018-06-30" },
        { start_date: "2018-01-01", end_date: { value: "2018-06-30" } },
        { start_date: "2018-07-01", end_date: "2018-06-30" }
      ]

      invalid_ranges.each do |parameters|
        seller_selects = capture_seller_selects do
          post "/api/sellers/unknown-seller/reports", params: parameters
        end

        assert_response :unprocessable_content, "expected #{parameters.inspect} to be rejected"
        assert_equal({ "error" => "invalid_date_range" }, response.parsed_body)
        assert_equal 0, seller_selects, "invalid dates must be rejected before seller lookup"
      end
      assert_no_enqueued_jobs
      assert_equal 0, SellerPerformanceReport.count
    end

    test "looks up sellers by external id and returns the exact not-found contract" do
      get_path = "/api/sellers/#{@seller.id}/reports"
      post get_path, params: { start_date: "2018-01-01", end_date: "2018-01-31" }

      assert_response :not_found
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)
      assert_no_enqueued_jobs
      assert_equal 0, SellerPerformanceReport.count
    end

    test "marks the identifiable report failed when enqueueing fails without leaking the exception" do
      with_class_method_stub(
        GenerateSellerPerformanceReportJob,
        :perform_later,
        ->(*) { raise "queue password leaked" }
      ) do
        post "/api/sellers/#{@seller.seller_id}/reports",
          params: { start_date: "2018-01-01", end_date: "2018-01-31" }
      end

      assert_response :service_unavailable
      assert_equal({ "error" => "report_enqueue_failed" }, response.parsed_body)
      refute_includes response.body, "queue password leaked"
      report = SellerPerformanceReport.find_by!(seller: @seller)
      assert_equal "failed", report.status
      assert_nil report.csv_data
    end

    test "status exposes the public contract and a download URL only when completed" do
      %w[pending processing failed].each do |status|
        report = create_report(status: status)

        get "/api/reports/#{report.public_id}"

        assert_response :ok
        assert_equal(
          { "report_id" => report.public_id, "seller_id" => @seller.seller_id, "status" => status },
          response.parsed_body
        )
      end

      completed = create_report(status: "completed", csv_data: "month,orders\n")
      get "/api/reports/#{completed.public_id}"

      assert_response :ok
      assert_equal %w[download_url report_id seller_id status], response.parsed_body.keys.sort
      assert_equal "completed", response.parsed_body["status"]
      assert_equal "http://www.example.com/api/reports/#{completed.public_id}/download",
        response.parsed_body["download_url"]
      refute_includes response.body, %Q("id":#{completed.id})
    end

    test "downloads only completed CSV reports and handles unknown public ids" do
      incomplete = create_report(status: "processing")
      get "/api/reports/#{incomplete.public_id}/download"

      assert_response :conflict
      assert_equal({ "error" => "report_not_ready" }, response.parsed_body)

      csv = "month,orders\n2018-01,1\n"
      completed = create_report(status: "completed", csv_data: csv)
      get "/api/reports/#{completed.public_id}/download"

      assert_response :ok
      assert_equal "text/csv", response.media_type
      assert_equal csv, response.body
      assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
      assert_match(/#{completed.public_id}/, response.headers.fetch("Content-Disposition"))

      get "/api/reports/#{SecureRandom.uuid}/download"
      assert_response :not_found
      assert_equal({ "error" => "report_not_found" }, response.parsed_body)
    end

    private

    def create_seller(external_id)
      Seller.create!(
        seller_id: external_id,
        zip_code_prefix: "01001",
        city: "sao paulo",
        state: "SP"
      )
    end

    def create_report(status:, csv_data: nil)
      SellerPerformanceReport.create!(
        seller: @seller,
        start_date: Date.new(2018, 1, 1),
        end_date: Date.new(2018, 1, 31),
        status: status,
        csv_data: csv_data
      )
    end

    def capture_seller_selects
      count = 0
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]
        next unless payload[:sql].match?(/\ASELECT\b/i)
        next unless payload[:sql].include?(%q(FROM "sellers"))

        count += 1
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
      count
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
end
