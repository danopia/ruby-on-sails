# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_wave.danopia.net_session',
  :secret      => '7bf9d91ba8a47ee09c1f01114de2be202d6b30819f8a4d84a1260f855e109541fe3640d6c97aacf5fb20d425588b8e4f6e04b1d3af3ebddc95ebdac1c05ae1f2'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
