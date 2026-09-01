module ApplicationHelper
  def admin_status_label(status)
    status.to_s.tr("_", " ").humanize
  end

  def admin_money(value)
    number_to_currency(value || 0, unit: "R$", separator: ",", delimiter: ".", format: "%u %n")
  end

  def admin_date(value, include_time: false)
    return "—" unless value

    value.strftime(include_time ? "%d/%m/%Y %H:%M" : "%d/%m/%Y")
  end
end
