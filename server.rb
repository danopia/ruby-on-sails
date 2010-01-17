require 'rubygems'
require 'hpricot'

require 'pp'
require 'yaml'

require 'sails'

#require 'agents/echoey'

Sails::Utils.connect_db

require 'lib/xmpp/packet'
require 'lib/xmpp/connection'
require 'lib/xmpp/component'
require 'lib/xmpp/waveserver'

# TODO: Set a 60-second timer to send a space to the XMPP server

EventMachine.run {
	provider = Sails::XMPP::WaveServer.load_and_connect 'sails.conf'

	#if provider.config['ping']
	#	puts "Sending a ping to #{provider.config['ping']} due to configuration."
	#	Sails::Server.new(provider, provider.config['ping'], provider.config['ping'])
	#end
  
  EM.start_server "127.0.0.1", 7849, Sails::Protocol::Server, provider
}
