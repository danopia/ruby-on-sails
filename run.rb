require 'rubygems'
require 'hpricot'

require 'server'

require 'pp'
require 'yaml'

require 'sails'

#require 'agents/echoey'

Sails::Utils.connect_db

#trap("INT") do
#	provider.remote.stop_service
#	puts 'OBAI'
#	exit
#end

#Thread.new do
	#provider.send_data ' ' while sleep 60
#end

require 'lib/xmpp/packet'
require 'lib/xmpp/connection'
require 'lib/xmpp/component'
require 'lib/xmpp/waveserver'

EventMachine.run {
	provider = Sails::XMPP::WaveServer.load_and_connect 'sails.conf'

	if provider.config['ping']
		puts "Sending a ping to #{provider.config['ping']} due to configuration."
		Sails::Server.new(provider, provider.config['ping'], provider.config['ping'], false)
	end
  
  EM.start_server "127.0.0.1", 7849, Sails::Protocol::Server, provider
}
