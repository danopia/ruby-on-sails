
module Sails

# Represents a server, remote or local, and tracks certificates, waves, and the
# queue of packets to send to a server once a connection is established.
class Server
	attr_accessor :provider, :certificates, :certificate_hash, :domain, :name, :waves, :queue, :state, :users
	
	# Create a new server.
	def initialize(provider, domain, name=nil, init=true)
		@provider = provider
		@domain = domain
		@name = name || domain
		@waves = {}
		@users = {}
		@queue = []
		@state = :uninited
		@certificates = []
		
		if init
			provider << self
		else
			provider.servers << self
		end
	end
	
	def certificate= cert
		self.certificates = [cert]
	end
	
	# Sets the certificate and generates a SHA2 hash in ASN.1/DER format, ready
	# to send to remote servers.
	def certificates= certs
		@certificates = certs.map do |cert|
			if cert.is_a? String
				unless cert.include? 'BEGIN CERTIFICATE'
					cert = Base64.encode64(Base64.decode64(cert))
					cert = "-----BEGIN CERTIFICATE-----\n#{cert}-----END CERTIFICATE-----\n"
				end
				cert = OpenSSL::X509::Certificate.new cert
			end
			cert
		end
		sequence = OpenSSL::ASN1::Sequence.new(@certificates.reverse)
		@certificate_hash = sha2 sequence.to_der
	end

	# Returns Base64-encoded certificates, ready for sending in XML packets.
	def certificates64
		@certificates.map {|cert| encode64 cert.to_der }
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
			
		elsif item.is_a? WaveUser
			@users[item.username] = item
			
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
	
	# Create a unique wave name, accross all waves known to this server
	def random_wave_name(length=12)
		name = random_string(length)
		name = random_string(length) while self[name]
		name
	end
end # class

end # module

