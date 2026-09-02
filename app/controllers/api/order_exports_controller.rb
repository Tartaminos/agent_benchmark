module Api
  class OrderExportsController < ActionController::API
    FILTERS = %i[order_status delivery_status customer_state purchase_from purchase_to].freeze

    def create
      filters, errors = parsed_filters
      unless errors.empty?
        return render json: { error: "invalid_filters", details: errors }, status: :unprocessable_content
      end

      export = OrderExport.create!(filters)
      enqueue(export)
    end

    def show
      export = find_export
      return export_not_found unless export

      response = { export_id: export.export_id, status: export.status }
      if export.status == "completed"
        response[:download_url] = download_api_order_export_path(export_id: export.export_id)
      end

      render json: response
    end

    def download
      export = find_export
      return export_not_found unless export
      unless export.status == "completed"
        return render json: { error: "export_not_ready" }, status: :conflict
      end

      send_data export.csv_content,
                type: "text/csv",
                disposition: "attachment",
                filename: "orders-#{export.export_id}.csv"
    end

    private

    def parsed_filters
      filters = {}
      errors = {}

      FILTERS.each do |name|
        next unless params.key?(name)

        value = params[name]
        unless value.is_a?(String)
          errors[name] = "must be a string"
          next
        end

        filters[name] = parse_filter(name, value, errors)
      end

      if filters[:purchase_from] && filters[:purchase_to] && filters[:purchase_from] > filters[:purchase_to]
        errors[:purchase_to] = "must be on or after purchase_from"
      end

      [ filters.compact, errors ]
    end

    def parse_filter(name, value, errors)
      case name
      when :order_status
        allowed_value(name, value, Order::ORDER_STATUSES, errors)
      when :delivery_status
        allowed_value(name, value, Order::DELIVERY_STATUSES, errors)
      when :customer_state
        allowed_value(name, value, Customer::STATES, errors)
      else
        strict_date(name, value, errors)
      end
    end

    def allowed_value(name, value, allowed, errors)
      return value if allowed.include?(value)

      errors[name] = "is not valid"
      nil
    end

    def strict_date(name, value, errors)
      unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        errors[name] = "must use YYYY-MM-DD"
        return
      end

      Date.iso8601(value)
    rescue Date::Error
      errors[name] = "must be a valid date"
      nil
    end

    def enqueue(export)
      GenerateOrderExportJob.perform_later(export.export_id)
      render json: { export_id: export.export_id, status: export.status }, status: :accepted
    rescue StandardError => error
      export.update_columns(csv_content: nil, status: "failed", updated_at: Time.current)
      Rails.logger.error(
        "Order export enqueue failed export_id=#{export.export_id} " \
          "error=#{error.class}: #{error.message}"
      )
      render json: { error: "export_enqueue_failed" }, status: :service_unavailable
    end

    def find_export
      OrderExport.find_by(export_id: params[:export_id])
    end

    def export_not_found
      render json: { error: "export_not_found" }, status: :not_found
    end
  end
end
