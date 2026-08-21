class CreateSellerPerformanceReports < ActiveRecord::Migration[8.1]
  def change
    create_table :seller_performance_reports do |t|
      t.uuid :report_id, null: false
      t.references :seller, null: false, foreign_key: true
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, null: false, default: "pending", limit: 10
      t.text :csv_content

      t.timestamps
    end

    add_index :seller_performance_reports, :report_id, unique: true
    add_index :order_items, %i[seller_id order_id]

    add_check_constraint :seller_performance_reports,
                         "status IN ('pending', 'processing', 'completed', 'failed')",
                         name: "seller_performance_reports_status_check"
    add_check_constraint :seller_performance_reports,
                         "start_date <= end_date",
                         name: "seller_performance_reports_date_range_check"
    add_check_constraint :seller_performance_reports,
                         "(status = 'completed' AND csv_content IS NOT NULL) OR " \
                           "(status <> 'completed' AND csv_content IS NULL)",
                         name: "seller_performance_reports_csv_status_check"
  end
end
