
module Sails

# Represents a server, remote or local, and tracks certificates, waves, and the
# queue of packets to send to a server once a connection is established.
class Server
	attr_accessor :provider, :certificates, :certificate_hash, :domain, :jids, :jid, :waves, :queue, :state, :users, :record
	
	# Create a new server.
	def initialize(provider, domain, jid=nil, init=true)
		@provider = provider
		@domain = domain
		@jid = jid
		@jids = []
		@waves = {}
		@users = {}
		@queue = []
		@state = :uninited
		@certificates = []
		
		@record = ::Server.find_by_domain domain
		@record ||= ::Server.find_by_jid jid || domain
		@record ||= ::Server.create :domain => domain, :jid => jid
		
		@certificate_hash = Utils.decode64 @record.signer_id if @record.signer_id
		@jid = @record.jid if @record.jid && @jid.nil?
		
		provider.servers << self
		disco 'items' if init
		
		load_waves
	end
	
	def load_waves
		return unless @record
		@record.waves.each do |wave_rec|
			wave = @provider.find_or_create_wave wave_rec.conv_root_path
			wave_rec.deltas.each do |delta_rec|
				Delta.from_record wave, delta_rec
			end
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
					cert = Base64.encode64(Base64.decode64(cert)) # add line breaks
					cert = "-----BEGIN CERTIFICATE-----\n#{cert}-----END CERTIFICATE-----\n"
				end
				cert = OpenSSL::X509::Certificate.new cert
			end
			cert
		end
		sequence = OpenSSL::ASN1::Sequence.new(@certificates.reverse)
		@certificate_hash = Utils::sha2 sequence.to_der
		
		@record.signer_id = Utils.encode64 @certificate_hash
		@record.save if @record.changed?
		
		@certificate_hash
	end

	# Returns Base64-encoded certificates, ready for sending in XML packets.
	def certificates64
		@certificates.map {|cert| Utils::encode64 cert.to_der }
	end
	
	def certificate_xml
		certificates64.map do |cert|
			"<certificate><![CDATA[#{cert}]]></certificate>"
		end.join ''
	end
	
	# Sets the server name.
	def jid= jid
		@provider.servers.delete @jid unless !@jid || @jid == @domain
		@provider.servers[jid] = self
		
		@record.jid = jid
		@record.save if @record.changed?
		
		@jid = jid
		
		return unless @state == :listing
		@state = :details
		ping
		@jid
	end
	
	# Look up a wave.
	#
	# Must be passed only the name, i.e. you must pass "meep" to get meep. No
	# domains will be handled.
	def [](name)
		@waves[name]
	end
	
	# Add a wave to the server's listing -or- queue/send a packet.
	def << item
		if item.is_a? Array # packet
			if @state == :ready
				@provider.send item[0], item[1], @jid, item[2], item[3]
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
			@provider.send packet[0], packet[1], @jid, packet[2], packet[3]
		end
		
		@queue = nil
	end
	
	# Create a unique wave name, accross all waves known to this server
	def random_wave_name(length=12)
		name = Utils.random_string(length)
		name = Utils.random_string(length) while self[name]
		name
	end
	
	def disco dance, jid=nil
		target = jid || (dance == 'items' ? @domain : @jid)
		@provider.disco target, dance
	end
	
	def ping
		@provider.queue 'message', 'normal', @jid || @domain, '<ping xmlns="http://waveprotocol.org/protocol/0.2/waveserver"/><request xmlns="urn:xmpp:receipts"/>'
	end
	
	def disco_jids
		p @state
		@state = :listing
		@jids.each {|jid| disco 'info', jid }
	end
end # class

end # module

