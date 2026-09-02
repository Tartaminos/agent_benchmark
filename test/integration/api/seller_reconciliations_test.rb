require "test_helper"

module Api
  class SellerReconciliationsTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    self.fixture_table_names = []

    setup do
      @customer = Customer.create!(
        customer_id: "reconciliation-customer",
        customer_unique_id: "reconciliation-shopper",
        zip_code_prefix: "01001",
        city: "sao paulo",
        state: "SP"
      )
      @target_seller = create_seller("reconciliation-target")
      @other_seller = create_seller("reconciliation-other")
      @product = Product.create!(product_id: "reconciliation-product")
    end

    teardown do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    test "create validates the seller and dates, then returns a pending public id and enqueues work" do
      assert_enqueued_with(job: GenerateSellerReconciliationJob) do
        post create_path, params: { start_date: "2024-01-01", end_date: "2024-01-31" }, as: :json
      end

      assert_response :accepted
      body = response.parsed_body
      assert_equal @target_seller.seller_id, body.fetch("seller_id")
      assert_equal "pending", body.fetch("status")
      assert_match(UUID_PATTERN, body.fetch("reconciliation_id"))

      reconciliation = SellerReconciliation.find_by!(reconciliation_id: body.fetch("reconciliation_id"))
      refute_equal reconciliation.id.to_s, reconciliation.reconciliation_id
      assert_equal [ reconciliation.reconciliation_id ], enqueued_jobs.fetch(0).fetch(:args)

      assert_no_difference("SellerReconciliation.count") do
        post "/api/sellers/unknown-seller/reconciliations",
             params: { start_date: "2024-01-01", end_date: "2024-01-31" }, as: :json
      end
      assert_response :not_found
      assert_equal({ "error" => "seller_not_found" }, response.parsed_body)

      invalid_requests = [
        { end_date: "2024-01-31" },
        { start_date: "2024-01-01" },
        { start_date: "2024-1-01", end_date: "2024-01-31" },
        { start_date: "2024-02-30", end_date: "2024-03-01" },
        { start_date: [ "2024-01-01" ], end_date: "2024-01-31" },
        { start_date: "2024-02-01", end_date: "2024-01-31" }
      ]

      invalid_requests.each do |params|
        assert_no_difference("SellerReconciliation.count", "unexpected record for #{params.inspect}") do
          post create_path, params:, as: :json
        end
        assert_response :unprocessable_entity
        assert_equal({ "error" => "invalid_reconciliation_parameters" }, response.parsed_body)
      end
    end

    test "status exposes every lifecycle state, final-only summary, and stable not-found responses" do
      reconciliation = create_reconciliation

      assert_status_contract(reconciliation, "pending")
      reconciliation.claim_for_processing!
      assert_status_contract(reconciliation, "processing")
      reconciliation.fail!
      assert_status_contract(reconciliation, "failed")

      completed = create_reconciliation(start_date: Date.new(2030, 1, 1), end_date: Date.new(2030, 1, 1))
      GenerateSellerReconciliationJob.perform_now(completed.reconciliation_id)
      get status_path(completed)

      assert_response :ok
      assert_equal(
        {
          "orders_checked" => 0,
          "matched_orders" => 0,
          "inconsistent_orders" => 0,
          "missing_payment_orders" => 0,
          "amount_mismatch_orders" => 0,
          "expected_value" => "0.00",
          "paid_value" => "0.00",
          "difference" => "0.00",
          "discrepancies_url" => discrepancies_path(completed)
        },
        response.parsed_body.fetch("summary")
      )

      get "/api/reconciliations/00000000-0000-4000-8000-000000000000"
      assert_response :not_found
      assert_equal({ "error" => "reconciliation_not_found" }, response.parsed_body)
    end

    test "generation reconciles distinct qualifying orders across full-order item and payment fan-out with inclusive dates" do
      matched = create_order("reconcile-a-matched", Time.utc(2024, 1, 1))
      create_item(matched, @target_seller, 1, "0.10", "0.20")
      create_item(matched, @target_seller, 2, "10.01", "1.02")
      create_item(matched, @other_seller, 3, "3.33", "0.44")
      create_payment(matched, 1, "5.05")
      create_payment(matched, 2, "10.05")

      mismatch = create_order("reconcile-b-mismatch", Time.utc(2024, 1, 31, 23, 59, 59, 999_999))
      create_item(mismatch, @target_seller, 1, "100.01", "0.09")
      create_payment(mismatch, 1, "100.00")
      create_payment(mismatch, 2, "0.09")

      missing = create_order("reconcile-c-missing", Time.utc(2024, 1, 15))
      create_item(missing, @target_seller, 1, "0.01", "0.02")

      outside = create_order("reconcile-outside", Time.utc(2024, 2, 1))
      create_item(outside, @target_seller, 1, "999.00", "1.00")
      other_only = create_order("reconcile-other-only", Time.utc(2024, 1, 15))
      create_item(other_only, @other_seller, 1, "999.00", "1.00")

      reconciliation = create_reconciliation
      GenerateSellerReconciliationJob.perform_now(reconciliation.reconciliation_id)
      reconciliation.reload

      assert_equal "completed", reconciliation.status
      assert_equal [ 3, 1, 2, 1, 1 ], [
        reconciliation.orders_checked,
        reconciliation.matched_orders,
        reconciliation.inconsistent_orders,
        reconciliation.missing_payment_orders,
        reconciliation.amount_mismatch_orders
      ]
      assert_equal [ "115.23", "115.19", "-0.04" ], [
        money(reconciliation.expected_value), money(reconciliation.paid_value), money(reconciliation.difference)
      ]
      assert_equal reconciliation.orders_checked,
                   reconciliation.matched_orders + reconciliation.inconsistent_orders
      assert_equal reconciliation.inconsistent_orders,
                   reconciliation.missing_payment_orders + reconciliation.amount_mismatch_orders
      assert_equal reconciliation.difference,
                   reconciliation.paid_value - reconciliation.expected_value

      assert_equal(
        [
          [ "reconcile-b-mismatch", "amount_mismatch", "100.10", "100.09", "-0.01" ],
          [ "reconcile-c-missing", "missing_payment", "0.03", "0.00", "-0.03" ]
        ],
        reconciliation.reconciliation_discrepancies.order(:external_order_id).map do |row|
          [ row.external_order_id, row.issue_type, money(row.expected_value), money(row.paid_value), money(row.difference) ]
        end
      )
    end

    test "completed discrepancies are externally identified, ordered, database-paginated, and strictly validate pagination" do
      %w[z-order a-order m-order].each_with_index do |order_id, index|
        order = create_order(order_id, Time.utc(2024, 1, 10) + index.seconds)
        create_item(order, @target_seller, 1, "1.00", "0.00")
        create_payment(order, 1, index == 1 ? "0.50" : "2.00")
      end
      reconciliation = create_reconciliation
      GenerateSellerReconciliationJob.perform_now(reconciliation.reconciliation_id)

      get discrepancies_path(reconciliation), params: { page: "2", per_page: "2" }
      assert_response :ok
      assert_equal [ "z-order" ], response.parsed_body.fetch("discrepancies").pluck("order_id")
      assert_equal(
        { "page" => 2, "per_page" => 2, "total_count" => 3, "total_pages" => 2 },
        response.parsed_body.fetch("pagination")
      )
      discrepancy = response.parsed_body.fetch("discrepancies").first
      assert_equal %w[order_id issue_type expected_value paid_value difference].sort, discrepancy.keys.sort

      get discrepancies_path(reconciliation)
      assert_response :ok
      assert_equal({ "page" => 1, "per_page" => 25 }, response.parsed_body.fetch("pagination").slice("page", "per_page"))

      get discrepancies_path(reconciliation), params: { per_page: "100" }
      assert_response :ok
      assert_equal 100, response.parsed_body.dig("pagination", "per_page")

      invalid_queries = [
        "page=0", "page=-1", "page=abc", "page=1.0", "page=01", "page=",
        "per_page=0", "per_page=-1", "per_page=abc", "per_page=1.0", "per_page=01",
        "per_page=101", "per_page[]=1"
      ]
      invalid_queries.each do |query|
        get "#{discrepancies_path(reconciliation)}?#{query}"
        assert_response :unprocessable_entity, "expected #{query.inspect} to be rejected"
        assert_equal({ "error" => "invalid_pagination" }, response.parsed_body)
      end
    end

    test "incomplete reconciliation never exposes seeded partial results" do
      %w[pending processing].each do |state|
        reconciliation = create_reconciliation
        reconciliation.claim_for_processing! if state == "processing"
        reconciliation.reconciliation_discrepancies.create!(
          external_order_id: "partial-#{state}",
          issue_type: "missing_payment",
          expected_value: "1.00",
          paid_value: "0.00",
          difference: "-1.00"
        )

        get discrepancies_path(reconciliation)
        assert_response :conflict
        assert_equal({ "error" => "reconciliation_not_completed" }, response.parsed_body)
        refute_includes response.body, "partial-#{state}"
      end
    end

    test "processing conflict rolls back generated rows, becomes failed, and duplicate deliveries cannot alter a terminal result" do
      first = create_order("a-new-row", Time.utc(2024, 1, 5))
      duplicate = create_order("z-duplicate-row", Time.utc(2024, 1, 6))
      [ first, duplicate ].each { |order| create_item(order, @target_seller, 1, "1.00", "0.00") }

      reconciliation = create_reconciliation
      reconciliation.reconciliation_discrepancies.create!(
        external_order_id: duplicate.order_id,
        issue_type: "missing_payment",
        expected_value: "1.00",
        paid_value: "0.00",
        difference: "-1.00"
      )

      GenerateSellerReconciliationJob.perform_now(reconciliation.reconciliation_id)
      reconciliation.reload

      assert_equal "failed", reconciliation.status
      assert_nil reconciliation.orders_checked
      assert_equal [ duplicate.order_id ], reconciliation.reconciliation_discrepancies.pluck(:external_order_id)
      get status_path(reconciliation)
      assert_response :ok
      assert_equal "failed", response.parsed_body.fetch("status")
      refute response.parsed_body.key?("summary")
      refute_includes response.body, "UniqueViolation"

      assert_no_changes -> { reconciliation.reconciliation_discrepancies.count } do
        GenerateSellerReconciliationJob.perform_now(reconciliation.reconciliation_id)
      end
      assert_equal "failed", reconciliation.reload.status

      successful = create_reconciliation(start_date: Date.new(2030, 1, 1), end_date: Date.new(2030, 1, 1))
      GenerateSellerReconciliationJob.perform_now(successful.reconciliation_id)
      original = successful.reload.attributes.slice(*SellerReconciliation::SUMMARY_ATTRIBUTES)
      assert_no_difference("ReconciliationDiscrepancy.count") do
        GenerateSellerReconciliationJob.perform_now(successful.reconciliation_id)
      end
      assert_equal original, successful.reload.attributes.slice(*SellerReconciliation::SUMMARY_ATTRIBUTES)
      assert_equal "completed", successful.status
    end

    test "generation uses bounded database statements as qualifying order count grows" do
      30.times do |index|
        order = create_order(format("bounded-%02d", index), Time.utc(2024, 1, 10) + index.seconds)
        create_item(order, @target_seller, 1, "1.00", "0.01")
        create_item(order, @other_seller, 2, "2.00", "0.02")
        create_payment(order, 1, "3.03")
      end
      reconciliation = create_reconciliation
      reconciliation.claim_for_processing!

      statements = capture_database_statements do
        SellerReconciliationGenerator.new(reconciliation).call
      end

      assert_equal 30, reconciliation.orders_checked
      assert_operator statements.count { |sql| sql.match?(/\AWITH qualifying_orders/i) }, :<=, 1
      assert_operator statements.count { |sql| sql.match?(/\ASELECT\b/i) }, :<=, 1
      assert_operator statements.length, :<=, 2
    end

    private

    UUID_PATTERN = Regexp.new(
      "\\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\z"
    )

    def create_path
      "/api/sellers/#{@target_seller.seller_id}/reconciliations"
    end

    def status_path(reconciliation)
      "/api/reconciliations/#{reconciliation.reconciliation_id}"
    end

    def discrepancies_path(reconciliation)
      "#{status_path(reconciliation)}/discrepancies"
    end

    def create_seller(seller_id)
      Seller.create!(seller_id:, zip_code_prefix: "20001", city: "rio de janeiro", state: "RJ")
    end

    def create_reconciliation(start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 1, 31))
      @target_seller.seller_reconciliations.create!(start_date:, end_date:)
    end

    def create_order(order_id, purchase_at)
      Order.create!(
        order_id:,
        customer: @customer,
        status: "delivered",
        purchase_at:,
        estimated_delivery_at: purchase_at + 7.days
      )
    end

    def create_item(order, seller, position, price, freight)
      OrderItem.create!(
        order:,
        seller:,
        product: @product,
        order_item_id: position,
        shipping_limit_at: order.purchase_at + 1.day,
        price:,
        freight_value: freight
      )
    end

    def create_payment(order, sequence, value)
      OrderPayment.create!(
        order:,
        payment_sequential: sequence,
        payment_type: "credit_card",
        payment_installments: 1,
        payment_value: value
      )
    end

    def money(value)
      format("%.2f", value)
    end

    def assert_status_contract(reconciliation, expected_status)
      get status_path(reconciliation)
      assert_response :ok
      assert_equal(
        {
          "reconciliation_id" => reconciliation.reconciliation_id,
          "seller_id" => @target_seller.seller_id,
          "status" => expected_status,
          "start_date" => "2024-01-01",
          "end_date" => "2024-01-31"
        },
        response.parsed_body
      )
    end

    def capture_database_statements
      statements = []
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        sql = payload[:sql].to_s.lstrip
        statements << sql unless payload[:cached] || payload[:name] == "SCHEMA" || sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)\b/i)
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
      statements
    end
  end

  class SellerReconciliationConcurrencyTest < ActiveSupport::TestCase
    self.fixture_table_names = []
    self.use_transactional_tests = false

    setup do
      @seller = Seller.create!(
        seller_id: "reconciliation-concurrent",
        zip_code_prefix: "20001",
        city: "rio de janeiro",
        state: "RJ"
      )
      @reconciliation = @seller.seller_reconciliations.create!(
        start_date: Date.new(2024, 1, 1),
        end_date: Date.new(2024, 1, 31)
      )
    end

    teardown do
      ReconciliationDiscrepancy.delete_all
      SellerReconciliation.delete_all
      Seller.where(seller_id: "reconciliation-concurrent").delete_all
    end

    test "concurrent claims have exactly one winner" do
      ready = Queue.new
      start = Queue.new
      results = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            candidate = SellerReconciliation.find(@reconciliation.id)
            ready << true
            start.pop
            results << candidate.claim_for_processing!
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:join)

      assert_equal [ false, true ], 2.times.map { results.pop }.sort_by(&:to_s)
      assert_equal "processing", @reconciliation.reload.status
    end
  end
end
