require 'sails'
require 'lib/xmpp_connection'
require 'yaml'

puts "Loading config"
begin
	config = YAML.load(File.open('sails.conf'))
rescue
	raise Sails::ProviderError, 'Could not read the sails.conf file. Make sure it exists and is proper YAML.'
end

def send data
	Sails::XMPPConnection.send data
end

Sails::XMPPConnection.on_packet do |packet|
	case packet.name
	
		when 'stream:error'
			error = packet.children.first.name rescue nil
			message = case error
				when 'conflict': 'The XMPP server denied this component because it conflicts with one that is already connected.'
				when nil: 'Unable to connect to XMPP. The server denied the component for an unknown reason.'
				else; "Unable to connect to XMPP: #{error}"
			end
			raise Sails::ProviderError, message
		
		when 'stream:stream'
			id = packet['id']
			
			puts "Stream opened, sending challenge response"

			key = Digest::SHA1.hexdigest(id + config['xmpp-password'])
			send "<handshake>#{key}</handshake>"
	end
end

Sails::XMPPConnection.start_loop config['xmpp-connect-host'], config['xmpp-connect-port'].to_i, config['service-name']
