require 'rubygems'
require 'hpricot'

require 'pp'
require 'yaml'

require 'sails'

require 'agents/echoey'

Sails::Utils.connect_db

#if config['ping']
	#puts "Sending a ping to #{config['ping']} due to configoration."
	#provider << Sails::Server.new(provider, config['ping'], config['ping'])
#end

trap("INT") do
	provider.remote.stop_service
	puts 'OBAI'
	exit
end

#Thread.new do
	#provider.send_data ' ' while sleep 60
#end

puts 'Entering program loop'

require 'lib/xmpp/packet'
require 'lib/xmpp/connection'
require 'lib/xmpp/component'
require 'lib/xmpp/waveserver'

EventMachine.run {
	provider = Sails::XMPP::WaveServer.load_and_connect 'sails.conf'
}
