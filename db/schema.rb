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

ActiveRecord::Schema[8.0].define(version: 2026_03_19_061411) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "gmail_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "email"
    t.string "access_token"
    t.string "encrypted_refresh_token"
    t.datetime "token_expires_at"
    t.datetime "last_sync_at"
    t.integer "sync_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_gmail_connections_on_user_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "product_name"
    t.string "brand"
    t.string "seller"
    t.decimal "amount"
    t.date "purchase_date"
    t.integer "warranty_duration"
    t.integer "warranty_status"
    t.text "ocr_data"
    t.string "file_url"
    t.string "original_filename"
    t.string "category"
    t.date "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ocr_status"
    t.text "ocr_error_message"
    t.string "model_number"
    t.string "product_image_url"
    t.text "description"
    t.boolean "product_enriched", default: false
    t.datetime "enriched_at"
    t.string "product_image_source"
    t.text "product_description"
    t.string "official_website"
    t.json "product_metadata"
    t.bigint "product_id"
    t.string "store_address"
    t.string "store_phone"
    t.string "store_gstin"
    t.string "invoice_number"
    t.string "invoice_time"
    t.decimal "mrp", precision: 10, scale: 2
    t.decimal "discount", precision: 10, scale: 2
    t.decimal "gst_percentage", precision: 5, scale: 2
    t.decimal "gst_amount", precision: 10, scale: 2
    t.string "color"
    t.text "specifications"
    t.string "part_number"
    t.string "serial_number"
    t.decimal "confidence_score", precision: 3, scale: 2
    t.json "metadata"
    t.index ["confidence_score"], name: "index_invoices_on_confidence_score"
    t.index ["expires_at"], name: "index_invoices_on_expires_at"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number"
    t.index ["ocr_status"], name: "index_invoices_on_ocr_status"
    t.index ["product_enriched"], name: "index_invoices_on_product_enriched"
    t.index ["product_id"], name: "index_invoices_on_product_id"
    t.index ["serial_number"], name: "index_invoices_on_serial_number"
    t.index ["user_id"], name: "index_invoices_on_user_id"
    t.index ["warranty_status"], name: "index_invoices_on_warranty_status"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.string "message", null: false
    t.integer "notification_type", null: false
    t.boolean "read", default: false, null: false
    t.string "action_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata"
    t.index ["created_at"], name: "idx_notifications_created_at"
    t.index ["user_id", "notification_type"], name: "idx_notifications_user_type"
    t.index ["user_id", "read"], name: "idx_notifications_user_read"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "product_warranties", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.string "component_name", null: false
    t.integer "warranty_months", null: false
    t.date "expires_at"
    t.date "purchase_date"
    t.string "warranty_text"
    t.boolean "reminder_sent", default: false
    t.datetime "last_reminder_sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["component_name"], name: "index_product_warranties_on_component_name"
    t.index ["expires_at", "reminder_sent"], name: "index_product_warranties_on_expires_at_and_reminder_sent"
    t.index ["expires_at"], name: "index_product_warranties_on_expires_at"
    t.index ["invoice_id", "component_name"], name: "index_product_warranties_on_invoice_id_and_component_name", unique: true
    t.index ["invoice_id"], name: "index_product_warranties_on_invoice_id"
    t.index ["reminder_sent", "expires_at"], name: "idx_pw_reminder_expires"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.string "brand"
    t.string "model_number"
    t.string "category"
    t.text "description"
    t.string "product_image_url"
    t.string "product_image_source"
    t.json "images"
    t.json "specifications"
    t.string "official_website"
    t.string "amazon_url"
    t.string "manufacturer_url"
    t.json "product_links"
    t.string "support_phone"
    t.string "support_email"
    t.string "support_website"
    t.text "support_info"
    t.json "contact_info"
    t.integer "standard_warranty_months"
    t.text "warranty_terms"
    t.string "warranty_info_url"
    t.string "data_source"
    t.datetime "last_synced_at"
    t.json "sync_metadata"
    t.string "search_keywords"
    t.integer "popularity_score", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand", "model_number"], name: "index_products_on_brand_and_model_number", unique: true
    t.index ["brand", "name"], name: "index_products_on_brand_and_name"
    t.index ["category"], name: "index_products_on_category"
    t.index ["model_number"], name: "index_products_on_model_number"
    t.index ["search_keywords"], name: "index_products_on_search_keywords"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.string "first_name"
    t.string "last_name"
    t.string "google_uid"
    t.string "avatar_url"
    t.integer "role"
    t.datetime "last_sign_in_at"
    t.integer "sign_in_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "email_verified", default: false, null: false
    t.string "verification_token"
    t.datetime "verification_sent_at"
    t.datetime "email_verified_at"
    t.datetime "last_app_reminder_sent_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verified"], name: "index_users_on_email_verified"
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true
    t.index ["verification_sent_at"], name: "index_users_on_verification_sent_at"
    t.index ["verification_token"], name: "index_users_on_verification_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "gmail_connections", "users"
  add_foreign_key "invoices", "products"
  add_foreign_key "invoices", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "product_warranties", "invoices", on_delete: :cascade
end
