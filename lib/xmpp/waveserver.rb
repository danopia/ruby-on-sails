module Sails
module XMPP
class WaveServer < Component
	handle 'iq', 'get' do |conn, packet, xml|
		if (xml/'query').any?
			if (xml/'query').first['xmlns'].include? 'items'
				packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#items\"><item jid=\"#{packet.connection.jid}\" name=\"#{conn.config['identity']}\"/></query>"
			else
				packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#info\"><identity category=\"collaboration\" type=\"ruby-on-sails\" name=\"#{conn.config['identity']}\"/><feature var=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></query>"
			end
		end
	end
	
	handle 'iq', 'result' do |conn, packet, xml|
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
end # waveserver
end # xmpp
end # sails
