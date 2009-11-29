
module Sails
module XMPP
	class Component < Connection
		attr_accessor :server_host, :server_port, :subdomain, :jid, :domain, :secret, :config
		
		def self.handle name, type, &blck
			@@handlers ||= {}
			@@handlers[name] ||= {}
			@@handlers[name][type] = blck
		end
		
		def self.load_and_connect filename
			begin
				config = YAML.load open('sails.conf')
			rescue
				raise Sails::ProviderError, "Could not read the #{path} file. Make sure it exists and is proper YAML."
			end

			server_host = config['xmpp-connect-host']
			server_port = config['xmpp-connect-port'].to_i

			connect server_host, server_port, config
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
					if @@handlers[packet.name] && @@handlers[packet.name][packet.type]
						@@handlers[packet.name][packet.type].call self, packet, node
					end
			end
		end
		
		def start_auth
			send_raw "<stream:stream xmlns=\"jabber:component:accept\" xmlns:stream=\"http://etherx.jabber.org/streams\" to=\"#{@jid}\">"
		end
		
		def initialize config
			super()
			load_config config
			start_auth
		end
		
		def load_config config
			@config = config
			
			@server_host = @config['xmpp-connect-host']
			@server_port = @config['xmpp-connect-port'].to_i
		
			@subdomain = @config['service-name']
			@domain = @config['domain-name']
			@jid = "#{@subdomain}.#{@domain}"
			
			@secret = @config['xmpp-password']
			
			load_certs config['certificate-chain']
			load_key config['private-key-path']
		end
		
		def load_certs paths
		end
		
		def load_key path
		end
		
	end
end
end
