require 'sails'
require 'lib/xmpp/packet'
require 'lib/xmpp/connection'
require 'lib/xmpp/component'
require 'yaml'

puts "Loading config"
begin
	$config = YAML.load(File.open('sails.conf'))
rescue
	raise Sails::ProviderError, 'Could not read the sails.conf file. Make sure it exists and is proper YAML.'
end

Sails::XMPP::Component.on_packet do |packet, xml|
	case [packet.name, packet.type]
	
		when ['iq', 'get']
			if (xml/'query').first.name == 'query'
				if (xml/'query').first['xmlns'].include? 'items'
					packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#items\"><item jid=\"#{packet.connection.jid}\" name=\"#{$config['identity']}\"/></query>"
				else
					packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#info\"><identity category=\"collaboration\" type=\"ruby-on-sails\" name=\"#{$config['identity']}\"/><feature var=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></query>"
				end
			end
		
	end
end

Sails::XMPP::Component.start_loop $config['xmpp-connect-host'], $config['xmpp-connect-port'].to_i, $config['service-name'], $config['domain-name'], $config['xmpp-password']
