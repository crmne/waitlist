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

ActiveRecord::Schema[8.1].define(version: 2026_10_25_190000) do
  create_table "products", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.string "site_url", null: false
    t.string "privacy_url", null: false
    t.string "from_address", null: false
    t.string "reply_to"
    t.json "allowed_origins", default: [], null: false
    t.string "thanks_url"
    t.string "approval"
    t.integer "keep_approved_days", default: 90, null: false
    t.json "questions", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "notify_address"
    t.integer "places_per_referral", default: 5, null: false
    t.index ["slug"], name: "index_products_on_slug", unique: true
  end

  create_table "signups", force: :cascade do |t|
    t.integer "product_id", null: false
    t.string "email", null: false
    t.json "answers", default: {}, null: false
    t.string "source", default: "form", null: false
    t.string "consent_text", null: false
    t.datetime "confirmation_sent_at"
    t.datetime "confirmed_at"
    t.datetime "approved_at"
    t.datetime "licence_issued_at"
    t.string "licence_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "referral_code"
    t.integer "referred_by_id"
    t.integer "referrals_count", default: 0, null: false
    t.integer "imported_referrals", default: 0, null: false
    t.index ["product_id", "confirmed_at", "approved_at", "created_at"], name: "idx_on_product_id_confirmed_at_approved_at_created__e186c70b46"
    t.index ["product_id", "email"], name: "index_signups_on_product_id_and_email", unique: true
    t.index ["product_id", "referral_code"], name: "index_signups_on_product_id_and_referral_code", unique: true
    t.index ["product_id"], name: "index_signups_on_product_id"
    t.index ["referred_by_id"], name: "index_signups_on_referred_by_id"
  end

  create_table "suppressions", force: :cascade do |t|
    t.integer "product_id", null: false
    t.string "email_digest", null: false
    t.datetime "created_at", null: false
    t.index ["product_id", "email_digest"], name: "index_suppressions_on_product_id_and_email_digest", unique: true
    t.index ["product_id"], name: "index_suppressions_on_product_id"
  end

  add_foreign_key "signups", "products"
  add_foreign_key "signups", "signups", column: "referred_by_id", on_delete: :nullify
  add_foreign_key "suppressions", "products"
end
