
module Sails
module XMPP
	class Component < Connection
		attr_accessor :server_host, :server_port, :subdomain, :jid, :domain, :secret, :config

		def initialize config_file
			super()
			
			load_config config_file
			
			start_auth
		end
		
		def me
			@jid
		end
		
		def disco target
			send 'iq', 'get', target, '<query xmlns="http://jabber.org/protocol/disco#items"/>'
		end
		
		def receive_object packet, node
			case packet.name
			
				when 'stream:error'
					error = node.children.first.name rescue nil
					message = case error
						when 'conflict': 'The XMPP server denied this component because it conflicts with one that is already connected.'
						when nil: 'Unable to connect to XMPP. The server denied the component for an unknown reason.'
						else; "Unable to connect to XMPP: #{error}"
					end
					raise Sails::ProviderError, message
				
				when 'stream:stream'
					id = packet.id
					
					puts "Stream opened, sending challenge response"

					key = Digest::SHA1.hexdigest id + @secret
					send_raw "<handshake>#{key}</handshake>"
				
				when 'handshake'
					puts "Server accepted component; we are now live"
					disco 'acmewave.com'
					#TODO: flush queues
				
				else
					@@handler.call self, packet, node
			end
		end
		
		def start_auth
			send_raw "<stream:stream xmlns=\"jabber:component:accept\" xmlns:stream=\"http://etherx.jabber.org/streams\" to=\"#{@jid}\">"
		end
		
		def load_config path
			puts "Loading YAML config"
			begin
				@config = YAML.load open(path)
				
				@server_host = @config['xmpp-connect-host']
				@server_port = @config['xmpp-connect-port'].to_i
			
				@subdomain = @config['service-name']
				@domain = @config['domain-name']
				@jid = "#{@subdomain}.#{@domain}"
				
				@secret = @config['xmpp-password']
			rescue
				raise Sails::ProviderError, "Could not read the #{path} file. Make sure it exists and is proper YAML."
			end
		end
		
	end
end
end
