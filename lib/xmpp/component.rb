
module Sails
module XMPP
	class Component < Connection
		attr_accessor :subdomain, :jid, :domain, :secret

		def initialize subdomain, domain, secret
			super()
			
			@subdomain = subdomain
			@domain = domain
			@jid = "#{@subdomain}.#{@domain}"
			@me = @jid
			@secret = secret
			
			start_auth
		rescue => e
			p e
			puts e.message, e.backtrace
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

					key = Digest::SHA1.hexdigest(id + @secret)
					send_raw "<handshake>#{key}</handshake>"
				
				when 'handshake'
					puts "Server accepted component; we are now live"
					#TODO: flush queues
				
				else
					@@handler.call packet, node
			end
		end
		
		def start_auth
			send_raw "<stream:stream xmlns=\"jabber:component:accept\" xmlns:stream=\"http://etherx.jabber.org/streams\" to=\"#{@jid}\">"
		end
		
	end
end
end
