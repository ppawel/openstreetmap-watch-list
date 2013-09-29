# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20130928181457) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "hstore"
  enable_extension "postgis"

# Could not dump table "changeset_tiles" because of following StandardError
#   Unknown type 'change' for column 'changes'

# Could not dump table "changesets" because of following StandardError
#   Unknown type 'geometry' for column 'bbox'

  create_table "nodes", id: false, force: true do |t|
    t.integer  "id",           limit: 8, null: false
    t.integer  "version",                null: false
    t.integer  "rev",                    null: false
    t.boolean  "visible",                null: false
    t.boolean  "current",                null: false
    t.integer  "user_id",                null: false
    t.datetime "tstamp",                 null: false
    t.integer  "changeset_id", limit: 8, null: false
    t.hstore   "tags",                   null: false
    t.integer  "geom",         limit: 0
  end

  add_index "nodes", ["changeset_id"], name: "idx_nodes_changeset_id", using: :btree
  add_index "nodes", ["geom"], name: "idx_nodes_geom", where: "(visible AND current)", using: :gist
  add_index "nodes", ["id"], name: "idx_nodes_node_id", using: :btree

  create_table "relation_members", id: false, force: true do |t|
    t.integer "relation_id", limit: 8, null: false
    t.integer "version",     limit: 8, null: false
    t.integer "member_id",   limit: 8, null: false
    t.string  "member_type", limit: 1, null: false
    t.text    "member_role",           null: false
    t.integer "sequence_id",           null: false
  end

  create_table "relations", id: false, force: true do |t|
    t.integer  "id",           limit: 8, null: false
    t.integer  "version",                null: false
    t.integer  "rev",                    null: false
    t.boolean  "visible",                null: false
    t.boolean  "current",                null: false
    t.integer  "user_id",                null: false
    t.datetime "tstamp",                 null: false
    t.integer  "changeset_id", limit: 8, null: false
    t.hstore   "tags",                   null: false
  end

  add_index "relations", ["changeset_id"], name: "idx_relations_changeset_id", using: :btree

  create_table "sidekiq_jobs", force: true do |t|
    t.string   "jid"
    t.string   "queue"
    t.string   "class_name"
    t.text     "args"
    t.boolean  "retry"
    t.datetime "enqueued_at"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.string   "status"
    t.string   "name"
    t.text     "result"
  end

  add_index "sidekiq_jobs", ["class_name"], name: "index_sidekiq_jobs_on_class_name", using: :btree
  add_index "sidekiq_jobs", ["enqueued_at"], name: "index_sidekiq_jobs_on_enqueued_at", using: :btree
  add_index "sidekiq_jobs", ["finished_at"], name: "index_sidekiq_jobs_on_finished_at", using: :btree
  add_index "sidekiq_jobs", ["jid"], name: "index_sidekiq_jobs_on_jid", using: :btree
  add_index "sidekiq_jobs", ["queue"], name: "index_sidekiq_jobs_on_queue", using: :btree
  add_index "sidekiq_jobs", ["retry"], name: "index_sidekiq_jobs_on_retry", using: :btree
  add_index "sidekiq_jobs", ["started_at"], name: "index_sidekiq_jobs_on_started_at", using: :btree
  add_index "sidekiq_jobs", ["status"], name: "index_sidekiq_jobs_on_status", using: :btree

  create_table "spatial_ref_sys", id: false, force: true do |t|
    t.integer "srid",                   null: false
    t.string  "auth_name", limit: 256
    t.integer "auth_srid"
    t.string  "srtext",    limit: 2048
    t.string  "proj4text", limit: 2048
  end

  create_table "users", id: false, force: true do |t|
    t.integer "id",   null: false
    t.text    "name", null: false
  end

  create_table "ways", id: false, force: true do |t|
    t.integer  "id",           limit: 8, null: false
    t.integer  "version",                null: false
    t.boolean  "visible",                null: false
    t.boolean  "current",                null: false
    t.integer  "user_id",                null: false
    t.datetime "tstamp",                 null: false
    t.integer  "changeset_id", limit: 8, null: false
    t.hstore   "tags",                   null: false
    t.integer  "nodes",        limit: 8, null: false, array: true
  end

  add_index "ways", ["changeset_id"], name: "idx_ways_changeset_id", using: :btree
  add_index "ways", ["nodes"], name: "idx_ways_nodes_id", using: :gin

end
