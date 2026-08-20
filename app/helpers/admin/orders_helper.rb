module Admin
  module OrdersHelper
    def admin_status_label(status)
      status.to_s.tr("_", " ").capitalize
    end

    def admin_status_class(status)
      case status.to_s
      when "delivered", "on_time" then "status-badge--success"
      when "late", "canceled", "unavailable" then "status-badge--danger"
      when "pending", "processing", "approved", "invoiced" then "status-badge--warning"
      when "shipped" then "status-badge--info"
      else "status-badge--neutral"
      end
    end

    def admin_date_time(value)
      value ? value.strftime("%b %-d, %Y %H:%M") : "Unavailable"
    end

    def admin_date(value)
      value ? value.strftime("%b %-d, %Y") : "Unavailable"
    end

    def admin_money(value)
      number_to_currency(value || 0, unit: "R$ ", separator: ",", delimiter: ".")
    end

    def admin_page_numbers(current_page, total_pages)
      return (1..total_pages).to_a if total_pages <= 7

      ([ 1, total_pages ] + ((current_page - 2)..(current_page + 2)).to_a)
        .select { |page| page.between?(1, total_pages) }
        .uniq
        .sort
    end
  end
end
