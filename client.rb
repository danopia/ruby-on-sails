require File.join(File.dirname(__FILE__), 'lib/protocol/client')

class PlainClient < Sails::Protocol::Client
end

PlainClient.start_loop 'danopia', 'test'
