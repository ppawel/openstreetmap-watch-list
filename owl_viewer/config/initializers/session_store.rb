# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_owl_viewer_session',
  :secret      => 'd4ab6206d44a74158a274e90e60f7e75befd4acfebcd6bd0404013de9144c697cf98c3266dbb7e489cfe81d40c6e8352c446fbbdbece3f3b2811b065cf961a63'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
