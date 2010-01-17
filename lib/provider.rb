
module Sails

# Most popular class. Represents the local server and the waves on it, and
# keeps a list of external servers.
class Provider
	attr_accessor :sock, :servers, :key, :domain, :name, :local, :packet_ids, :ready
	
	# Create a new provider.
	def initialize(domain, subdomain='wave', sock=nil)
		@domain = domain
		@name = [subdomain, domain] * '.'
		@servers = ServerList.new self
		@sock = sock
		@packet_ids = {}
		@ready = false

		@local = Server.new self, @domain, @name, false
		@local.state = :local
	end

	alias ready? ready
	
	# Marks the provider as ready and flushes all queued packets. Also starts a
	# remote if not already started.
	def ready!
		return if ready?
		@ready = true
		flush
	end
	
	# Load the provider's certificate from a file.
	def load_certs(paths)
		@local.certificates = paths.map {|path| open(path).read }
	end
	
	# Load the provider's private key from a file.
	def load_key(path)
		@key = OpenSSL::PKey::RSA.new(open(path).read)
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
		if type.to_i > 0 || type =~ /^purple/ || type.include?('postsigner') || type.include?('history') || type.include?('submit')
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
			(item.server || @local) << item
			
		else
			raise ArgumentError, 'expected a Server or Wave'
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
	
	def read_plain
		message = @sock.recv 1024
		puts "Recieved: \e[33m#{message}\e[0m"
		Hpricot(message)
	end
	
	def read
		message = ''
		until @sock.closed?
			message += @sock.recv 1024
			
			if !message || message.empty?
				raise ProviderError, 'XMPP component connection closed unexpectantly. (got blank packet)'
			elsif message.include? '</stream:stream>'
				raise ProviderError, 'Server closed the XMPP component connection.'
			end
			
			doc = Hpricot("<packet>#{message}<done/></packet>")
			
			next if message[-1,1] != '>'
			next if (doc/'packet/done').empty? # Didn't get the whole packet
			
			puts "Recieved: \e[33m#{message}\e[0m"
			
			return doc.root.children.select {|node| node.name != 'done'}
		end
		nil
	end
	
	def find_or_create_wave path
		path =~ /^(.+)\/w\+(.+)\/(.+)$/
		domain, name, wavelet = $1, $2, $3
		domain.sub!('wave://', '')
		
		server = find_or_create_server domain
		return server[name] if server[name]
		
		wave = Wave.new self, name, server
		self << wave
		wave
	end
	
	def find_or_create_server name
		if @servers.keys.include? name.downcase
			@servers[name]
		else
			Server.new self, name
		end
	end
	
	def find_or_create_user address
		return address if address.is_a? WaveUser
		
		username, domain = address.downcase.split '@', 2

		server = find_or_create_server domain
		
		return server.users[username] if server.users[username]
		WaveUser.new self, address
	end
end # class

end # module

