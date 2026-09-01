class CreateSellerPerformanceReports < ActiveRecord::Migration[8.1]
  def change
    create_table :seller_performance_reports do |t|
      t.uuid :report_id, null: false
      t.references :seller, null: false, foreign_key: true
      t.string :status, null: false, limit: 10, default: "pending"
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.text :csv_data

      t.timestamps
    end

    add_index :seller_performance_reports, :report_id, unique: true
    add_index :seller_performance_reports, [ :seller_id, :created_at ]
    add_check_constraint :seller_performance_reports,
                         "status IN ('pending', 'processing', 'completed', 'failed')",
                         name: "seller_performance_reports_valid_status"
    add_check_constraint :seller_performance_reports,
                         "start_date <= end_date",
                         name: "seller_performance_reports_valid_date_range"
    add_check_constraint :seller_performance_reports,
                         "(status = 'completed' AND csv_data IS NOT NULL) OR " \
                           "(status <> 'completed' AND csv_data IS NULL)",
                         name: "seller_performance_reports_csv_matches_status"
  end
end
