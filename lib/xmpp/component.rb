
module Sails
module XMPP
class Component < Connection
	attr_accessor :server_host, :server_port, :subdomain, :jid, :domain, :secret, :config, :ready
	
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
	
	def disco target, dance='items'
		queue 'iq', 'get', target, "<query xmlns=\"http://jabber.org/protocol/disco##{dance}\"/>"
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
				unless id
					error = (node/'stream:error').first.children.first.name rescue nil
					message = case error
						when 'conflict': 'The XMPP server denied this component because it conflicts with one that is already connected.'
						when nil: 'Unable to connect to XMPP. The server denied the component for an unknown reason.'
						else; "Unable to connect to XMPP: #{error}"
					end
					raise Sails::ProviderError, message
				end
				
				puts "Stream opened, sending challenge response"

				key = Digest::SHA1.hexdigest id + @secret
				send_raw "<handshake>#{key}</handshake>"
			
			when 'handshake'
				puts "Server accepted component; we are now live"
				ready!
			
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
		
		@ready = false
		@queue = []
		
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
	end

	alias ready? ready

	# Marks the provider as ready and flushes all queued packets. Also starts a
	# remote if not already started.
	def ready!
		return if ready?
		@ready = true
		flush
	end
	
	# Add a wave to the correct server -or- Add a server to the main list
	def << item
		if item.is_a? Array
			if ready?
				send *item
			else
				@queue << item
			end
			
		else
			raise ArgumentError, 'expected a Server or Wave or Array' # TODO: change message
		end
	end
	
	# Easier way to use << to queue packets
	def queue *args
		self << args
	end
	
	# Flush the packet buffer
	def flush
		return unless ready?
		
		@queue.each do |packet|
			self << packet # send
		end
		
		@queue.clear
	end
	
end # component class
end # xmpp module
end # sails module
