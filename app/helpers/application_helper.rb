module ApplicationHelper
  def admin_currency(value)
    number_to_currency(value || 0, unit: "R$ ", separator: ",", delimiter: ".")
  end

  def admin_time(value, date_only: false)
    return tag.span("—", class: "admin-orders__missing") unless value

    format = date_only ? "%Y-%m-%d" : "%Y-%m-%d %H:%M"
    tag.time(value.strftime(format), datetime: value.iso8601)
  end

  def admin_filter_error_attributes(field, invalid_fields)
    return {} unless invalid_fields.include?(field)

    { aria: { invalid: "true", describedby: "filter-errors" } }
  end

  def admin_status_label(status)
    status.to_s.tr("_", " ").humanize
  end

  def admin_pagination_pages(current_page, total_pages)
    [ 1, current_page - 1, current_page, current_page + 1, total_pages ]
      .select { |page| page.between?(1, total_pages) }
      .uniq
      .sort
  end
end
