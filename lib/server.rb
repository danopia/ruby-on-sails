
module Sails

# Represents a server, remote or local, and tracks certificates, waves, and the
# queue of packets to send to a server once a connection is established.
class Server
	attr_accessor :provider, :certificate, :certificate_hash, :domain, :name, :waves, :queue, :state
	
	# Create a new server.
	def initialize(provider, domain, name=nil)
		@provider = provider
		@domain = domain
		@name = name || domain
		@waves = {}
		@queue = []
		@state = :uninited
	end
	
	# Sets the certificate and generates a SHA2 hash in ASN.1/DER format, ready
	# to send to remote servers.
	def certificate=(cert)
		cert = OpenSSL::X509::Certificate.new(cert) if cert.is_a? String
		@certificate = cert
		@certificate_hash = sha2 "0\202\003\254#{@certificate.to_der}"
	end

	# Returns a Base64-encoded certificate, ready for sending in XML packets.
	def certificate64
		encode64 @certificate.to_der
	end
	
	# Sets the server name.
	def name=(new_name)
		@provider.servers.delete @name unless !@name || @name == @domain
		@provider.servers[new_name] = self
		
		@name = new_name
	end
	
	# Look up a wave.
	#
	# Must be passed only the name, i.e. you must pass "meep" to get meep. No
	# domains will be handled.
	def [](name)
		@waves[name]
	end
	
	# Add a wave to the server's listing -or- queue/send a packet.
	def <<(item)
		if item.is_a? Array # packet
			if @state == :ready
				@provider.send_xml item[0], item[1], @name, item[2], item[3]
			else
				@queue << item
			end
			
		elsif item.is_a? Wave
			@waves[item.name] = item
			
		else
			raise ArgumentError, 'expected an Array (packet) or Wave'
		end
	end
	
	# Send the queue out (state must be :ready)
	def flush
		return false unless @state == :ready && @provider.ready?
		return nil unless @queue && @queue.any?
		
		@queue.each do |packet|
			@provider.send_xml packet[0], packet[1], @name, packet[2], packet[3]
		end
		
		@queue = nil
	end
	
	# Generate a random alphanumeric string
	def self.random_name(length=12)
		@letters ||= ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
		([''] * length).map { @letters[rand * @letters.size] }.join('')
	end
	
	# Create a unique wave name, accross all waves known to this server
	def random_wave_name(length=12)
		name = Server.random_name(length)
		name = Server.random_name(length) while self[name]
		name
	end
end # class

end # module

