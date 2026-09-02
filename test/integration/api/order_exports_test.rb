require "test_helper"
require "csv"

module Api
  class OrderExportsTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    self.fixture_table_names = []

    setup do
      @customer_sp = create_customer("customer-export-sp", "SP")
      @customer_rj = create_customer("customer-export-rj", "RJ")
      @product = Product.create!(product_id: "product-export")
      @seller = Seller.create!(
        seller_id: "seller-export",
        zip_code_prefix: "20001",
        city: "rio de janeiro",
        state: "RJ"
      )
    end

    teardown do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    test "create accepts valid combined filters and returns a queued public UUID before generation" do
      filters = {
        order_status: "delivered",
        delivery_status: "late",
        customer_state: "SP",
        purchase_from: "2024-01-01",
        purchase_to: "2024-01-31"
      }

      assert_enqueued_with(job: GenerateOrderExportJob) do
        post "/api/order_exports", params: filters, as: :json
      end

      assert_response :accepted
      assert_equal "pending", response.parsed_body.fetch("status")
      export_id = response.parsed_body.fetch("export_id")
      assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, export_id)

      export = OrderExport.find_by!(export_id:)
      assert_equal filters.stringify_keys, export.filters
      refute_equal export.id.to_s, export_id
      assert_not export.file.attached?, "the create request must not synchronously generate the CSV"
      assert_equal [ export_id ], enqueued_jobs.fetch(0).fetch(:args)
    end

    test "rejects unsupported, structured, malformed, impossible, and inverted filters" do
      invalid_requests = [
        { order_status: "refunded" },
        { order_status: [ "delivered" ] },
        { delivery_status: "in_transit" },
        { delivery_status: [ "late" ] },
        { customer_state: "sp" },
        { customer_state: [ "SP" ] },
        { purchase_from: "2024-1-01" },
        { purchase_to: "2024-02-30" },
        { purchase_from: [ "2024-01-01" ] },
        { purchase_from: "2024-02-01", purchase_to: "2024-01-31" }
      ]

      invalid_requests.each do |params|
        assert_no_difference("OrderExport.count", "unexpected export for #{params.inspect}") do
          post "/api/order_exports", params:, as: :json
        end

        assert_response :unprocessable_entity, "expected #{params.inspect} to be rejected"
        assert_equal({ "error" => "invalid_order_export_filters" }, response.parsed_body)
      end
    end

    test "status exposes lifecycle without a premature URL and unknown identifiers return 404" do
      export = OrderExport.create!

      get "/api/order_exports/#{export.export_id}"
      assert_response :ok
      assert_equal({ "export_id" => export.export_id, "status" => "pending" }, response.parsed_body)

      export.claim_for_processing!
      get "/api/order_exports/#{export.export_id}"
      assert_response :ok
      assert_equal({ "export_id" => export.export_id, "status" => "processing" }, response.parsed_body)

      export.fail!
      get "/api/order_exports/#{export.export_id}"
      assert_response :ok
      assert_equal({ "export_id" => export.export_id, "status" => "failed" }, response.parsed_body)

      get "/api/order_exports/00000000-0000-4000-8000-000000000000"
      assert_response :not_found
      assert_equal({ "error" => "order_export_not_found" }, response.parsed_body)

      get "/api/order_exports/not-a-uuid"
      assert_response :not_found
      assert_equal({ "error" => "order_export_not_found" }, response.parsed_body)
    end

    test "download is unavailable before completion and completed content is downloadable as CSV" do
      export = OrderExport.create!

      get "/api/order_exports/#{export.export_id}/download"
      assert_response :conflict
      assert_equal({ "error" => "order_export_not_ready" }, response.parsed_body)
      refute_includes response.media_type, "text/csv"

      GenerateOrderExportJob.perform_now(export.export_id)
      export.reload

      get "/api/order_exports/#{export.export_id}"
      assert_response :ok
      assert_equal "completed", response.parsed_body.fetch("status")
      assert_equal "/api/order_exports/#{export.export_id}/download", response.parsed_body.fetch("download_url")

      get response.parsed_body.fetch("download_url")
      assert_response :ok
      assert_equal "text/csv", response.media_type
      assert_equal OrderExportGenerator::HEADERS, CSV.parse(response.body).fetch(0)

      get "/api/order_exports/00000000-0000-4000-8000-000000000000/download"
      assert_response :not_found
      assert_equal({ "error" => "order_export_not_found" }, response.parsed_body)

      get "/api/order_exports/not-a-uuid/download"
      assert_response :not_found
      assert_equal({ "error" => "order_export_not_found" }, response.parsed_body)
    end

    test "CSV has the exact contract, deterministic order, fan-out-safe precise totals, and external identifiers" do
      later = create_order(
        "order-export-z",
        customer: @customer_rj,
        purchase_at: Time.utc(2024, 1, 2, 3, 4, 5),
        delivered_at: nil
      )
      tied_b = create_order(
        "order-export-b",
        customer: @customer_sp,
        purchase_at: Time.utc(2024, 1, 1, 12),
        estimated_at: Time.utc(2024, 1, 10),
        delivered_at: Time.utc(2024, 1, 10)
      )
      tied_a = create_order(
        "order-export-a",
        customer: @customer_sp,
        purchase_at: Time.utc(2024, 1, 1, 12),
        estimated_at: Time.utc(2024, 1, 10),
        delivered_at: Time.utc(2024, 1, 10) + 0.001
      )
      create_item(tied_a, 1, price: "0.10", freight: "0.20")
      create_item(tied_a, 2, price: "10.01", freight: "1.02")
      create_payment(tied_a, 1, "5.05")
      create_payment(tied_a, 2, "6.28")
      create_item(tied_b, 1, price: "2.00", freight: "0.00")
      create_payment(tied_b, 1, "2.00")

      rows = completed_csv

      assert_equal OrderExportGenerator::HEADERS, rows.shift
      assert_equal %w[order-export-a order-export-b order-export-z], rows.map(&:first)
      assert_equal(
        [
          tied_a.order_id,
          @customer_sp.customer_id,
          "SP",
          "delivered",
          "late",
          "2024-01-01T12:00:00.000Z",
          "2024-01-10T00:00:00.000Z",
          "2024-01-10T00:00:00.001Z",
          "10.11",
          "1.22",
          "11.33",
          "11.33"
        ],
        rows.first
      )
      assert_equal %w[2.00 0.00 2.00 2.00], rows.second.last(4)
      assert_equal %w[0.00 0.00 0.00 0.00], rows.third.last(4)
      refute rows.flatten.include?(tied_a.id.to_s)
      refute rows.flatten.include?(@customer_sp.id.to_s)
      assert_equal %w[late on_time pending], rows.map { |row| row.fetch(4) }
    end

    test "order, delivery, customer, and independent inclusive date filters select only qualifying rows" do
      create_order(
        "match-all-filters",
        customer: @customer_sp,
        status: "delivered",
        purchase_at: Time.utc(2024, 1, 31, 23, 59, 59),
        delivered_at: Time.utc(2024, 2, 11)
      )
      create_order(
        "wrong-order-status",
        customer: @customer_sp,
        status: "shipped",
        purchase_at: Time.utc(2024, 1, 31, 12),
        delivered_at: Time.utc(2024, 2, 11)
      )
      create_order(
        "wrong-delivery-status",
        customer: @customer_sp,
        status: "delivered",
        purchase_at: Time.utc(2024, 1, 31, 12),
        delivered_at: Time.utc(2024, 2, 10)
      )
      create_order(
        "wrong-customer-state",
        customer: @customer_rj,
        status: "delivered",
        purchase_at: Time.utc(2024, 1, 31, 12),
        delivered_at: Time.utc(2024, 2, 11)
      )
      create_order(
        "before-from-boundary",
        customer: @customer_sp,
        status: "delivered",
        purchase_at: Time.utc(2024, 1, 30, 23, 59, 59),
        delivered_at: Time.utc(2024, 2, 11)
      )
      create_order(
        "after-to-boundary",
        customer: @customer_sp,
        status: "delivered",
        purchase_at: Time.utc(2024, 2, 1),
        delivered_at: Time.utc(2024, 2, 11)
      )

      combined = completed_csv(
        "order_status" => "delivered",
        "delivery_status" => "late",
        "customer_state" => "SP",
        "purchase_from" => "2024-01-31",
        "purchase_to" => "2024-01-31"
      )
      assert_equal %w[match-all-filters], combined.drop(1).map(&:first)

      from_only = completed_csv("purchase_from" => "2024-02-01")
      assert_equal %w[after-to-boundary], from_only.drop(1).map(&:first)

      to_only = completed_csv("purchase_to" => "2024-01-30")
      assert_equal %w[before-from-boundary], to_only.drop(1).map(&:first)
    end

    test "an empty result completes with only the header" do
      rows = completed_csv("customer_state" => "AC")

      assert_equal [ OrderExportGenerator::HEADERS ], rows
    end

    test "processing failure remains queryable, hides exception details, and exposes no partial file" do
      invalid_internal_date = "2024-99-99"
      export = OrderExport.create!(filters: { "purchase_from" => invalid_internal_date })

      GenerateOrderExportJob.perform_now(export.export_id)

      export.reload
      assert_equal "failed", export.status
      assert_not export.file.attached?

      get "/api/order_exports/#{export.export_id}"
      assert_response :ok
      assert_equal({ "export_id" => export.export_id, "status" => "failed" }, response.parsed_body)
      refute_includes response.body, invalid_internal_date

      get "/api/order_exports/#{export.export_id}/download"
      assert_response :conflict
      refute_includes response.body, invalid_internal_date
    end

    test "duplicate processing of a completed export is an idempotent no-op" do
      order = create_order("order-idempotent", customer: @customer_sp)
      create_item(order, 1, price: "1.23", freight: "0.45")
      create_payment(order, 1, "1.68")
      export = OrderExport.create!

      GenerateOrderExportJob.perform_now(export.export_id)
      export.reload
      original_blob_id = export.file.blob.id
      original_csv = export.file.download

      assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
        GenerateOrderExportJob.perform_now(export.export_id)
      end

      export.reload
      assert_equal "completed", export.status
      assert_equal original_blob_id, export.file.blob.id
      assert_equal original_csv, export.file.download
      assert_equal 1, CSV.parse(original_csv).drop(1).length
    end

    private

    def create_customer(customer_id, state)
      Customer.create!(
        customer_id:,
        customer_unique_id: "unique-#{customer_id}",
        zip_code_prefix: "01001",
        city: "city",
        state:
      )
    end

    def create_order(
      order_id,
      customer:,
      purchase_at: Time.utc(2024, 1, 1),
      status: "delivered",
      estimated_at: Time.utc(2024, 2, 10),
      delivered_at: nil
    )
      Order.create!(
        order_id:,
        customer:,
        status:,
        purchase_at:,
        estimated_delivery_at: estimated_at,
        delivered_customer_at: delivered_at
      )
    end

    def create_item(order, position, price:, freight:)
      OrderItem.create!(
        order:,
        product: @product,
        seller: @seller,
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

    def completed_csv(filters = {})
      export = OrderExport.create!(filters:)
      GenerateOrderExportJob.perform_now(export.export_id)
      export.reload
      assert_equal "completed", export.status
      CSV.parse(export.file.download)
    end
  end
end
