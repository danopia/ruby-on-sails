
module Sails

# Variation of Hash with a degree of case-insensitive keys.
class ServerList < Hash
	def [](server)
		return nil unless server
		super server.downcase
	end
	def []=(name, server)
		return nil unless name
		super name.downcase, server
	end
	def delete(server)
		return nil unless server
		super server.downcase
	end
	def << server
		self[server.domain] = server
		self[server.name] = server
	end
end

# Most popular class. Represents the local server and the waves on it, and
# keeps a list of external servers.
class Provider
	attr_accessor :sock, :servers, :key, :domain, :name, :local, :packet_ids, :ready
	
	# Create a new provider.
	def initialize(domain, subdomain='wave', sock=nil)
		subdomain = "#{subdomain}." if subdomain

		@domain = domain
		@name = "#{subdomain}#{domain}"
		@servers = ServerList.new
		@sock = sock
		@packet_ids = {}
		@ready = false

		@local = Server.new(self, @domain, @name)
		@local.state = :local
		@servers << @local
	end

	alias ready? ready
	
	# Marks the provider as ready and flushes all queued packets.
	def ready!
		return if ready?
		@ready = true
		flush
	end
	
	# Load the provider's certificate from a file.
	def load_cert(path)
		@local.certificate = OpenSSL::X509::Certificate.new(open(path).read)
	end
	
	# Load the provider's private key from a file.
	def load_key(path)
		@key = OpenSSL::PKey::RSA.new(File.open(path).read)
	end
	
	# Signs a chunk of data using the private key.
	def sign(data)
		@key.sign OpenSSL::Digest::SHA1.new, data
	end

	# Create a socket to the XMPP server.
	def connect_sock(host='localhost', port=5275)
		@sock.close if @sock && !@sock.closed?

		puts "Connecting to XMPP server at #{host}:#{port}"
		@sock = TCPSocket.new host, port
	end

	# Generated a random packet ID for XMPP in the form of ####-##.
	def random_packet_id
		"#{(rand*10000).to_i}-#{(rand*100).to_i}"
	end

	# Sends a data chunk to the XMPP server and logs it to console.
	def send_data data
		puts "Sent: \e[0;35m#{data}\e[0m" if data.size > 1
		@sock.print data
		data
	end

	# Sends a frankenstein's monster XML packet down to the XMPP server.
	#
	# Pass a packet ID in the +type+ field to make it into a 'result' with the
	# correct ID.
	def send_xml(name, type, to, contents, id=nil)
		if type.to_i > 0 || type =~  /^purple/
			id = type
			type = 'result'
		else
			id ||= random_packet_id
		end

		@packet_ids[id] = send_data("<#{name} type=\"#{type}\" id=\"#{id}\" to=\"#{to}\" from=\"#{@name}\">#{contents}</#{name}>")
		id
	end
	
	# Look up a wave.
	#
	# Can be passed in domain/w+name format for a certain wave, or name format
	# to search all known waves.
	def [](name)
		if name =~ /^(.+)\/w\+(.+)$/
			server = @servers[$1.downcase]
			return nil unless server
			server[$2]
		else
			# allow fallback to not specifing a domain

			@servers.values.each do |server|
				return server[name] if server[name]
			end
			
			nil
		end
	end
	
	# Add a wave to the correct server -or- Add a server to the main list
	def <<(item)
		if item.is_a? Server
			@servers[item.domain] = item
			init_server item
		
		elsif item.is_a? Wave
			server = @servers[item.host]
			unless server
				server = Server.new(self, item.host, item.host)
				self << server
			end
			
			server << item
			
		else
			raise ArgumentError, 'expected a Server or Wave'
		end
	end
	
	# Init a Server connection by pinging it and sending a cert. Called for you
	# if/when you << the Server to the Provider.
	def init_server server
		return unless self.ready? && server.state == :uninited

		target = server.name || server.domain
		if target == 'wavesandbox.com'
			send_xml 'iq', 'get', "wave.#{target}",
				'<query xmlns="http://jabber.org/protocol/disco#info"/>'
			server.state = :listing
			server.name = "wave.#{server.domain}"
		else
			send_xml 'iq', 'get', target,
				'<query xmlns="http://jabber.org/protocol/disco#items"/>'
			server.state = :sent_item_request
		end
	end
	
	# Flush all the remote servers.
	def flush
		return unless ready?
		
		@servers.each_value do |server|
			if server.state == :uninited
				init_server server
			else
				server.flush
			end
		end
	end
end # class

end # module

