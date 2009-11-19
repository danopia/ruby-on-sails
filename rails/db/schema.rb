# This file is auto-generated from the current state of the database. Instead of editing this file, 
# please use the migrations feature of Active Record to incrementally modify your database, and
# then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database schema. If you need
# to create the application database on another system, you should be using db:schema:load, not running
# all the migrations from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 2) do

  create_table "contacts", :force => true do |t|
    t.integer "user1_id",      :null => false
    t.integer "user2_id"
    t.string  "user2_address"
  end

  create_table "deltas", :force => true do |t|
    t.integer  "wave_id",    :null => false
    t.integer  "server_id"
    t.integer  "user_id"
    t.string   "author",     :null => false
    t.string   "signer_id",  :null => false
    t.string   "raw"
    t.string   "signature"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "groups", :force => true do |t|
    t.integer "user_id"
    t.string  "address",     :null => false
    t.string  "title",       :null => false
    t.text    "description"
    t.boolean "public"
  end

  create_table "memberships", :force => true do |t|
    t.integer "user_id"
    t.integer "group_id",                :null => false
    t.string  "address"
    t.integer "level",    :default => 1
  end

  create_table "servers", :force => true do |t|
    t.string   "domain",     :null => false
    t.string   "jid"
    t.string   "signer_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "users", :force => true do |t|
    t.string   "login",                              :null => false
    t.string   "email",                              :null => false
    t.string   "crypted_password",                   :null => false
    t.string   "password_salt",                      :null => false
    t.string   "persistence_token",                  :null => false
    t.string   "single_access_token",                :null => false
    t.string   "perishable_token",                   :null => false
    t.integer  "login_count",         :default => 0, :null => false
    t.integer  "failed_login_count",  :default => 0, :null => false
    t.datetime "last_request_at"
    t.datetime "current_login_at"
    t.datetime "last_login_at"
    t.string   "current_login_ip"
    t.string   "last_login_ip"
    t.string   "display_name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "waves", :force => true do |t|
    t.integer  "server_id"
    t.string   "name",                          :null => false
    t.boolean  "public",     :default => false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end
