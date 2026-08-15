class CreateSellerPerformanceReports < ActiveRecord::Migration[8.1]
  def change
    create_table :seller_performance_reports do |t|
      t.uuid :public_id, null: false
      t.references :seller, null: false, foreign_key: true
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, null: false, default: "pending", limit: 10
      t.text :csv_data

      t.timestamps
    end

    add_index :seller_performance_reports, :public_id, unique: true
    add_check_constraint :seller_performance_reports,
                         "status IN ('pending', 'processing', 'completed', 'failed')",
                         name: "seller_performance_reports_status"
    add_check_constraint :seller_performance_reports,
                         "start_date <= end_date",
                         name: "seller_performance_reports_date_range"
    add_check_constraint :seller_performance_reports,
                         <<~SQL.squish,
                           (status = 'completed' AND csv_data IS NOT NULL)
                           OR (status <> 'completed' AND csv_data IS NULL)
                         SQL
                         name: "seller_performance_reports_csv_state"
  end
end
