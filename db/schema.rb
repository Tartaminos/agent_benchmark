# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_02_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "customers", force: :cascade do |t|
    t.string "city", limit: 32, null: false
    t.datetime "created_at", null: false
    t.string "customer_id", limit: 32, null: false
    t.string "customer_unique_id", limit: 32, null: false
    t.string "state", limit: 2, null: false
    t.datetime "updated_at", null: false
    t.string "zip_code_prefix", limit: 5, null: false
    t.index ["customer_id"], name: "index_customers_on_customer_id", unique: true
    t.index ["customer_unique_id"], name: "index_customers_on_customer_unique_id"
  end

  create_table "geolocations", force: :cascade do |t|
    t.string "city", limit: 38, null: false
    t.datetime "created_at", null: false
    t.decimal "latitude", precision: 17, scale: 14, null: false
    t.decimal "longitude", precision: 17, scale: 14, null: false
    t.string "state", limit: 2, null: false
    t.datetime "updated_at", null: false
    t.string "zip_code_prefix", limit: 5, null: false
    t.index ["zip_code_prefix"], name: "index_geolocations_on_zip_code_prefix"
  end

  create_table "order_exports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "csv_content"
    t.string "customer_state", limit: 2
    t.string "delivery_status", limit: 10
    t.uuid "export_id", null: false
    t.string "order_status", limit: 11
    t.date "purchase_from"
    t.date "purchase_to"
    t.string "status", limit: 10, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["export_id"], name: "index_order_exports_on_export_id", unique: true
    t.check_constraint "purchase_from IS NULL OR purchase_to IS NULL OR purchase_from <= purchase_to", name: "order_exports_date_range_check"
    t.check_constraint "status::text = 'completed'::text AND csv_content IS NOT NULL OR status::text <> 'completed'::text AND csv_content IS NULL", name: "order_exports_csv_status_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "order_exports_status_check"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "freight_value", precision: 10, scale: 2, null: false
    t.bigint "order_id", null: false
    t.integer "order_item_id", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.bigint "product_id", null: false
    t.bigint "seller_id", null: false
    t.datetime "shipping_limit_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id", "order_item_id"], name: "index_order_items_on_order_id_and_order_item_id", unique: true
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
    t.index ["seller_id", "order_id"], name: "index_order_items_on_seller_id_and_order_id"
    t.index ["seller_id"], name: "index_order_items_on_seller_id"
  end

  create_table "order_payments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.integer "payment_installments", null: false
    t.integer "payment_sequential", null: false
    t.string "payment_type", limit: 11, null: false
    t.decimal "payment_value", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id", "payment_sequential"], name: "index_order_payments_on_order_id_and_payment_sequential", unique: true
    t.index ["order_id"], name: "index_order_payments_on_order_id"
  end

  create_table "order_reviews", force: :cascade do |t|
    t.datetime "answer_at", null: false
    t.text "comment_message"
    t.string "comment_title", limit: 26
    t.datetime "created_at", null: false
    t.datetime "creation_at", null: false
    t.bigint "order_id", null: false
    t.string "review_id", limit: 32, null: false
    t.integer "score", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_reviews_on_order_id"
    t.index ["review_id"], name: "index_order_reviews_on_review_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.datetime "delivered_carrier_at"
    t.datetime "delivered_customer_at"
    t.datetime "estimated_delivery_at", null: false
    t.string "order_id", limit: 32, null: false
    t.datetime "purchase_at", null: false
    t.string "status", limit: 11, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["order_id"], name: "index_orders_on_order_id", unique: true
    t.index ["purchase_at", "order_id"], name: "index_orders_on_purchase_at_and_order_id"
  end

  create_table "product_category_translations", force: :cascade do |t|
    t.string "category_name", limit: 46, null: false
    t.string "category_name_english", limit: 39, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_name"], name: "index_product_category_translations_on_category_name", unique: true
  end

  create_table "products", force: :cascade do |t|
    t.string "category_name", limit: 46
    t.datetime "created_at", null: false
    t.integer "description_length"
    t.integer "height_cm"
    t.integer "length_cm"
    t.integer "name_length"
    t.integer "photos_quantity"
    t.string "product_id", limit: 32, null: false
    t.datetime "updated_at", null: false
    t.integer "weight_g"
    t.integer "width_cm"
    t.index ["product_id"], name: "index_products_on_product_id", unique: true
  end

  create_table "seller_performance_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "csv_content"
    t.date "end_date", null: false
    t.uuid "report_id", null: false
    t.bigint "seller_id", null: false
    t.date "start_date", null: false
    t.string "status", limit: 10, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["report_id"], name: "index_seller_performance_reports_on_report_id", unique: true
    t.index ["seller_id"], name: "index_seller_performance_reports_on_seller_id"
    t.check_constraint "start_date <= end_date", name: "seller_performance_reports_date_range_check"
    t.check_constraint "status::text = 'completed'::text AND csv_content IS NOT NULL OR status::text <> 'completed'::text AND csv_content IS NULL", name: "seller_performance_reports_csv_status_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "seller_performance_reports_status_check"
  end

  create_table "seller_reconciliation_discrepancies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "difference", precision: 20, scale: 2, null: false
    t.decimal "expected_value", precision: 20, scale: 2, null: false
    t.string "external_order_id", limit: 32, null: false
    t.string "issue_type", limit: 15, null: false
    t.decimal "paid_value", precision: 20, scale: 2, null: false
    t.bigint "seller_reconciliation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["seller_reconciliation_id", "external_order_id"], name: "idx_reconciliation_discrepancies_order", unique: true
    t.check_constraint "expected_value >= 0::numeric AND paid_value >= 0::numeric AND difference = (paid_value - expected_value)", name: "reconciliation_discrepancies_money_check"
    t.check_constraint "issue_type::text = 'missing_payment'::text AND paid_value = 0::numeric AND difference = (- expected_value) OR issue_type::text = 'amount_mismatch'::text AND difference <> 0::numeric", name: "reconciliation_discrepancies_classification_check"
    t.check_constraint "issue_type::text = ANY (ARRAY['missing_payment'::character varying, 'amount_mismatch'::character varying]::text[])", name: "reconciliation_discrepancies_issue_type_check"
  end

  create_table "seller_reconciliations", force: :cascade do |t|
    t.bigint "amount_mismatch_orders"
    t.datetime "created_at", null: false
    t.decimal "difference", precision: 20, scale: 2
    t.date "end_date", null: false
    t.decimal "expected_value", precision: 20, scale: 2
    t.bigint "inconsistent_orders"
    t.bigint "matched_orders"
    t.bigint "missing_payment_orders"
    t.bigint "orders_checked"
    t.decimal "paid_value", precision: 20, scale: 2
    t.uuid "processing_token"
    t.uuid "reconciliation_id", null: false
    t.bigint "seller_id", null: false
    t.date "start_date", null: false
    t.string "status", limit: 10, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["reconciliation_id"], name: "index_seller_reconciliations_on_reconciliation_id", unique: true
    t.index ["seller_id"], name: "index_seller_reconciliations_on_seller_id"
    t.check_constraint "(status::text = 'processing'::text) = (processing_token IS NOT NULL)", name: "seller_reconciliations_processing_token_check"
    t.check_constraint "expected_value >= 0::numeric AND paid_value >= 0::numeric AND difference = (paid_value - expected_value)", name: "seller_reconciliations_money_invariants_check"
    t.check_constraint "orders_checked = (matched_orders + inconsistent_orders) AND inconsistent_orders = (missing_payment_orders + amount_mismatch_orders)", name: "seller_reconciliations_count_invariants_check"
    t.check_constraint "orders_checked >= 0 AND matched_orders >= 0 AND inconsistent_orders >= 0 AND missing_payment_orders >= 0 AND amount_mismatch_orders >= 0", name: "seller_reconciliations_nonnegative_counts_check"
    t.check_constraint "start_date <= end_date", name: "seller_reconciliations_date_range_check"
    t.check_constraint "status::text = 'completed'::text AND orders_checked IS NOT NULL AND matched_orders IS NOT NULL AND inconsistent_orders IS NOT NULL AND missing_payment_orders IS NOT NULL AND amount_mismatch_orders IS NOT NULL AND expected_value IS NOT NULL AND paid_value IS NOT NULL AND difference IS NOT NULL AND processing_token IS NULL OR status::text <> 'completed'::text AND orders_checked IS NULL AND matched_orders IS NULL AND inconsistent_orders IS NULL AND missing_payment_orders IS NULL AND amount_mismatch_orders IS NULL AND expected_value IS NULL AND paid_value IS NULL AND difference IS NULL", name: "seller_reconciliations_summary_status_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "seller_reconciliations_status_check"
  end

  create_table "sellers", force: :cascade do |t|
    t.string "city", limit: 40, null: false
    t.datetime "created_at", null: false
    t.string "seller_id", limit: 32, null: false
    t.string "state", limit: 2, null: false
    t.datetime "updated_at", null: false
    t.string "zip_code_prefix", limit: 5, null: false
    t.index ["seller_id"], name: "index_sellers_on_seller_id", unique: true
  end

  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "order_items", "sellers"
  add_foreign_key "order_payments", "orders"
  add_foreign_key "order_reviews", "orders"
  add_foreign_key "orders", "customers"
  add_foreign_key "seller_performance_reports", "sellers"
  add_foreign_key "seller_reconciliation_discrepancies", "seller_reconciliations", on_delete: :cascade
  add_foreign_key "seller_reconciliations", "sellers"
end
