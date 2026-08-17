module Admin::OrdersHelper
  def admin_money(value)
    number_to_currency(value || 0, unit: "R$ ", separator: ",", delimiter: ".")
  end

  def admin_date(value, include_time: true)
    return "—" unless value

    value.strftime(include_time ? "%d/%m/%Y %H:%M" : "%d/%m/%Y")
  end

  def delivery_status_for(order)
    return "pending" unless order.delivered_customer_at

    order.delivered_customer_at <= order.estimated_delivery_at ? "on_time" : "late"
  end

  def status_label(status)
    status.to_s.tr("_", " ").humanize
  end

  def admin_page_params(overrides = {})
    @query_params.merge(overrides).compact
  end

  def admin_detail_params
    admin_page_params.except(:order_id).tap do |detail_params|
      detail_params[:list_order_id] = @query_params[:order_id] if @query_params[:order_id].present?
    end
  end
end
