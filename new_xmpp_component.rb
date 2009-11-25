require 'sails'
require 'lib/xmpp_connection'
require 'yaml'

puts "Loading config"
begin
	$config = YAML.load(File.open('sails.conf'))
rescue
	raise Sails::ProviderError, 'Could not read the sails.conf file. Make sure it exists and is proper YAML.'
end

class Packet
	attr_accessor :name, :type, :to, :from, :id, :node

	def self.send_raw data
		Sails::XMPPConnection.send data
	end

	def self.send name, type, to, data, id=nil
		send_raw "<#{name} type=\"#{type}\" id=\"#{id}\" to=\"#{to}\" from=\"#{$name}\">#{data}</#{name}>"
	end

	def initialize xml
		@node = xml
		
		@name = xml.name
		@type = xml['type'] || 'default'
		@to   = xml['to']
		@from = xml['from']
		@id   = xml['id']
	end
	
	def respond data
		Packet.send @name, 'result', @from, data, @id
	end
end

def got_packet xml
	packet = Packet.new xml
	case [packet.name, packet.type]
	
		when ['iq', 'get']
			if (xml/'query').first.name == 'query'
				handle_disco packet, (xml/'query').first['xmlns'].split('#').last
			end
	end
end

def handle_disco packet, type
	if type == 'items'
		packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#items\"><item jid=\"#{$name}\" name=\"#{$config['identity']}\"/></query>"
	else
		packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#info\"><identity category=\"collaboration\" type=\"ruby-on-sails\" name=\"#{$config['identity']}\"/><feature var=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></query>"
	end
end

Sails::XMPPConnection.on_packet do |xml|
	case xml.name
	
		when 'stream:error'
			error = xml.children.first.name rescue nil
			message = case error
				when 'conflict': 'The XMPP server denied this component because it conflicts with one that is already connected.'
				when nil: 'Unable to connect to XMPP. The server denied the component for an unknown reason.'
				else; "Unable to connect to XMPP: #{error}"
			end
			raise Sails::ProviderError, message
		
		when 'stream:stream'
			id = xml['id']
			
			puts "Stream opened, sending challenge response"

			key = Digest::SHA1.hexdigest(id + $config['xmpp-password'])
			Packet.send_raw "<handshake>#{key}</handshake>"
		
		when 'handshake'
			puts "Server accepted component; we are now live"
			#TODO: flush queues
		
		else
			got_packet xml
	end
end

$name = "#{$config['service-name']}.#{$config['domain-name']}"

Sails::XMPPConnection.start_loop $config['xmpp-connect-host'], $config['xmpp-connect-port'].to_i, $name
