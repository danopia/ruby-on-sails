require 'sails'

class PlainClient < Sails::Protocol::Client
end

PlainClient.start_loop 'danopia', 'test'
