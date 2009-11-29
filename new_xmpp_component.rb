require 'sails'
require 'lib/xmpp/packet'
require 'lib/xmpp/connection'
require 'lib/xmpp/component'

#component = Sails::XMPP::Component.new
#component.load_config 'sails.conf'

Sails::XMPP::Component.on_packet do |conn, packet, xml|
	case [packet.name, packet.type]
	
		when ['iq', 'get']
			if (xml/'query').any?
				if (xml/'query').first['xmlns'].include? 'items'
					packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#items\"><item jid=\"#{packet.connection.jid}\" name=\"#{conn.config['identity']}\"/></query>"
				else
					packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#info\"><identity category=\"collaboration\" type=\"ruby-on-sails\" name=\"#{conn.config['identity']}\"/><feature var=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></query>"
				end
			end
			
		when ['iq', 'result']
			if (xml/'query').any?
				if (xml/'query').first['xmlns'].include? 'items'
					(xml/'item').each do |node|
						conn.send 'iq', 'get', node['jid'], "<query xmlns=\"http://jabber.org/protocol/disco#info\" />"
					end
				else
					wave = (xml/'feature[@var=http://waveprotocol.org/protocol/0.2/waveserver]').any?
					if wave
						puts "Got a Wave JID: #{packet.from}"
					else
						puts 'Got a non-wave JID'
					end
				end
			end
		
	end
end

config = YAML.load open('sails.conf')

server_host = config['xmpp-connect-host']
server_port = config['xmpp-connect-port'].to_i

puts server_host, server_port
Sails::XMPP::Component.start_loop server_host, server_port, 'sails.conf'
#$config['xmpp-connect-host'], $config['xmpp-connect-port'].to_i, $config['service-name'], $config['domain-name'], $config['xmpp-password']
