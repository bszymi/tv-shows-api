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

ActiveRecord::Schema[8.0].define(version: 2025_06_12_231552) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "distributors", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_distributors_on_name", unique: true
  end

  create_table "release_dates", force: :cascade do |t|
    t.bigint "tv_show_id", null: false
    t.string "country"
    t.date "release_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country"], name: "index_release_dates_on_country"
    t.index ["release_date"], name: "index_release_dates_on_release_date"
    t.index ["tv_show_id", "country"], name: "index_release_dates_on_tv_show_id_and_country", unique: true
    t.index ["tv_show_id"], name: "index_release_dates_on_tv_show_id"
  end

  create_table "tv_shows", force: :cascade do |t|
    t.integer "external_id"
    t.string "name"
    t.string "show_type"
    t.string "language"
    t.string "status"
    t.integer "runtime"
    t.date "premiered"
    t.text "summary"
    t.string "official_site"
    t.string "image_url"
    t.decimal "rating", precision: 3, scale: 1
    t.bigint "distributor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["distributor_id"], name: "index_tv_shows_on_distributor_id"
    t.index ["external_id"], name: "index_tv_shows_on_external_id", unique: true
  end

  add_foreign_key "release_dates", "tv_shows"
  add_foreign_key "tv_shows", "distributors"
end
