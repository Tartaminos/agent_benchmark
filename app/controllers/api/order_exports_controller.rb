module Api
  class OrderExportsController < ApplicationController
    FILTER_KEYS = %i[order_status delivery_status customer_state purchase_from purchase_to].freeze
    ORDER_STATUSES = %w[approved canceled created delivered invoiced processing shipped unavailable].freeze
    CUSTOMER_STATES = %w[AC AL AM AP BA CE DF ES GO MA MG MS MT PA PB PE PI PR RJ RN RO RR RS SC SE SP TO].freeze
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    protect_from_forgery with: :null_session
    before_action :load_order_export, only: %i[show download]

    def create
      filters = normalized_filters
      return render_invalid_filters unless filters

      order_export = OrderExport.create!(filters: filters)
      return render_enqueue_failure(order_export) unless enqueue(order_export)

      render json: export_payload(order_export), status: :accepted
    end

    def show
      render json: export_payload(@order_export)
    end

    def download
      unless @order_export.completed? && @order_export.file.attached?
        return render json: { error: "order_export_not_ready" }, status: :conflict
      end

      filename = "orders-#{@order_export.export_id}.csv"
      response.headers["Content-Type"] = "text/csv; charset=utf-8"
      response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
        disposition: "attachment",
        filename: filename
      )
      self.response_body = Enumerator.new do |body|
        @order_export.file.blob.download { |chunk| body << chunk }
      end
    end

    private

    def load_order_export
      export_id = params[:export_id]
      @order_export = OrderExport.find_by(export_id: export_id) if UUID.match?(export_id)
      render json: { error: "order_export_not_found" }, status: :not_found unless @order_export
    end

    def normalized_filters
      values = params.permit(*FILTER_KEYS)
      filters = {}

      return unless optional_member(values, filters, :order_status, ORDER_STATUSES)
      return unless optional_member(values, filters, :delivery_status, Order::DELIVERY_STATUSES)
      return unless optional_member(values, filters, :customer_state, CUSTOMER_STATES)
      return unless optional_date(values, filters, :purchase_from)
      return unless optional_date(values, filters, :purchase_to)

      from = filters["purchase_from"]
      to = filters["purchase_to"]
      return if from && to && Date.iso8601(from) > Date.iso8601(to)

      filters
    end

    def optional_member(values, filters, key, allowed)
      return true unless params.key?(key)

      value = values[key]
      return false unless value.is_a?(String) && allowed.include?(value)

      filters[key.to_s] = value
      true
    end

    def optional_date(values, filters, key)
      return true unless params.key?(key)

      value = values[key]
      return false unless value.is_a?(String) && ISO_DATE.match?(value)

      filters[key.to_s] = Date.iso8601(value).iso8601
      true
    rescue Date::Error
      false
    end

    def export_payload(order_export)
      payload = { export_id: order_export.export_id, status: order_export.status }
      if order_export.completed? && order_export.file.attached?
        payload[:download_url] = download_api_order_export_path(export_id: order_export.export_id)
      end
      payload
    end

    def enqueue(order_export)
      GenerateOrderExportJob.perform_later(order_export.export_id)
      true
    rescue StandardError => error
      Rails.logger.error("Could not enqueue order export #{order_export.export_id} (#{error.class})")
      false
    end

    def render_enqueue_failure(order_export)
      order_export.fail!
      render json: { error: "order_export_enqueue_failed", export_id: order_export.export_id },
             status: :service_unavailable
    end

    def render_invalid_filters
      render json: { error: "invalid_order_export_filters" }, status: :unprocessable_entity
    end
  end
end
