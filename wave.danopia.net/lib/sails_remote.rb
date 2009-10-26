#require 'openssl'
require 'drb'

# A class that's focused for use with DRb. There are a few methods that just
# call deeper methods, since DRb only sends method calls to the server if
# called on the main DRbObject. If it weren't for these methods, a DRb client
# wouldn't be able to do much.
class SailsRemote
	attr_accessor :drb, :provider
	
	# Serve a remote up
	def self.serve(provider, host=':9000')
		remote = SailsRemote.new(provider)
		remote.drb = DRb.start_service("druby://#{host}", remote)
		remote
	end
	
	# Connect to a remote
	def self.connect(host=':9000')
		DRbObject.new nil, "druby://#{host}"
	end
	
	# Create a remote for the provider
	def initialize(provider)
		@provider = provider
		@drb = nil
	end
	
	# DRb's URI
	def uri
		@drb.uri if @drb
	end
	
	# Shuts down the DRb server
	def stop_service
		@drb.stop_service if @drb
		@drb = nil
	end
	
	# Returns a list of waves from the provider
	def waves
		@provider.waves
	end
	
	# Look up and return a wave
	def [](name)
		@provider[name]
	end
	# Add a wave
	def <<(wave)
		@provider << wave
	end
	
	# Add a delta to a wave (faster to give the wave's name). Also propagates the
	# delta.
	def add_delta(wave, delta)
		if wave.is_a? Wave
			wave << delta# unless wave.deltas.include?(delta)
			wave = wave.name
		end
		self[wave] << delta
		delta.propagate
	end
end


# Most popular class. Represents the local server and the waves on it, and
# keeps a list of external certificates.
class Provider
	attr_accessor :certs, :cert_hash, :domain, :name, :waves, :sock
	
	# Create a new provider.
	def initialize(domain, subdomain='wave')
		@certs = {}
		@cert_hash = nil
		@domain = domain
		@name = "#{subdomain}.#{domain}"
		@waves = {}
		@sock = nil
		
		@letters = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
		@certs[domain] = open("#{domain}.cert").read.split("\n")[1..-2].join('')
	end
	
	# Generate and return the certificate SHA2 hash in ASN.1/DER format, ready to
	# send to remote servers.
	def cert_hash
		return @cert_hash if @cert_hash
		@cert_hash = decode64(@certs[@domain])
		@cert_hash = Digest::SHA2.digest "0\202\003\254#{@cert_hash}"
	end
	
	# Return a wave.
	#
	# Can be passed in domain/w+name format for a certain wave, or w+name format
	# to search all known waves.
	def [](name)
		return @waves[name] if @waves.has_key?(name)
		
		# allow fallback to not specifing a domain
		waves = @waves.values.select{|wave|wave.name == name}
		return nil if waves.empty?
		waves.first
	end
	
	# Add a wave to the main listing
	def <<(wave)
		@waves[wave.path] = wave
	end
	
	# Generate a random alphanumeric string
	def random_name(length=12)
		('' * length).map { @letters[rand * @letters.size] }.join('')
	end
	
	# Create a unique wave name, accross all waves known to this server
	def random_wave_name(length=12)
		while name=random_name(length)
			return name unless self[name]
		end
	end
end


# Represents an unknown delta. Used for the fake "version 0" and for gaps in
# history, so we can store hashes without storing anything else.
class FakeDelta
	attr_accessor :wave, :version, :hash
	
	# Create a fake delta. It defaults to being the infamous "version 0" for a
	# wave. If you need to be anything else, you can pass the version/hash to
	# the initializer or use version= and hash=.
	def initialize(wave, version=0, hash=nil)
		@wave = wave
		@version = version
		@hash = hash || "wave://#{wave.conv_root_path}"
	end
end

# Represents the addition of a participant to a wave.
#
# === Usage ===
# 	delta << AddUserOp.new('me@danopia.net')
#
# 	operation = AddUserOp.new('echoey@danopia.net')
# 	operation.to_s #=> 'Added echoey@danopia.net to the wave'
# 	operation.to_hash #=> {0 => ['echoey@danopia.net']}
#
# 	operation = AddUserOp.new(['echoey@acmewave.com', 'meep@acmewave.com'])
# 	operation.to_s #=> 'Added echoey@acmewave.com, meep@acmewave.com to the wave'
# 	operation.to_hash #=> {0 => ['echoey@danopia.net', 'meep@acmewave.com'']}
class AddUserOp
	attr_accessor :who
	
	def initialize(who)
		who = [who] unless who.is_a? Array
		@who = who
	end
	
	def to_hash
		{:added => @who}
	end
	
	def to_s
		"Added #{@who.join(', ')} to the wave"
	end
end

# Represents the removal of a participant from a wave.
#
# === Usage ===
# 	delta << RemoveUserOp.new('me@danopia.net')
#
# 	operation = RemoveUserOp.new('echoey@danopia.net')
# 	operation.to_s #=> 'Removed echoey@danopia.net from the wave'
# 	operation.to_hash #=> {1 => ['echoey@danopia.net']}
#
# 	operation = RemoveUserOp.new(['echoey@acmewave.com', 'meep@acmewave.com'])
# 	operation.to_s #=> 'Removed echoey@acmewave.com, meep@acmewave.com from the wave'
# 	operation.to_hash #=> {1 => ['echoey@danopia.net', 'meep@acmewave.com'']}
class RemoveUserOp
	attr_accessor :who
	
	def initialize(who)
		who = [who] unless who.is_a? Array
		@who = who
	end
	
	def to_hash
		{:removed => @who}
	end
	
	def to_s
		"Removed #{@who.join(', ')} from the wave"
	end
end

# Represents the mutation of the contents of a wavelet. TODO: Fix and document!
class MutateOp
	attr_accessor :document_id, :components
	
	def initialize(document_id=nil, components=[])
		components = [components] unless components.is_a? Array
		
		@document_id = document_id
		@components = components
	end
	
	def self.parse(data)
		doc = data[:document_id]
		components = data[:mutation][:components]
		MutateOp.new(doc, components)
	end
	
	def to_hash
		{:mutate => {
			:mutation => {
				:components => @components},
			:document_id => @document_id}}
	end
	
	def to_s
		components.last.values.first
	end
end

# Represents a version of a wavelet where the provider has details (as opposed
# to FakeDelta).
class Delta
	attr_accessor :wave, :version, :author, :operations, :time
	
	# Frozen deltas are considered to be unchanging, so the byte form is cached
	# to greatly speed up the creation of packets.
	attr_reader :frozen
	
	# Create a new delta. Defaults to applying itself to the latest delta from
	# the wave, but if you want to add older history in, you can override it with
	# version=. You should also try to set the time, if you can get it.
	def initialize(wave, author=nil)
		@wave = wave
		@author = author
		@version = wave.newest_version + 1
		@operations = []
		@time = Time.now
		@frozen = false
	end
	
	# Parses an incoming delta, taking the wavelet name (from the XML attribute)
	# and the bytestring (doesn't handle Base64). It will handle adding the delta
	# to a wave, creating the wave if it doesn't exist, and sending out the delta
	# to any other servers that need it. (TODO: Only do this when local delta)
	def self.parse provider, wavelet, data
		data = WaveProtoBuffer.parse(:delta, data) if data.is_a? String
		
		wavelet =~ /^(.+)\/w\+(.+)\/(.+)$/
		wave_domain, wave_name, wavelet_name = $1, $2, $3
		puts "Parsing #{wave_domain}'s #{wavelet_name} wavelet for w+#{wave_name}"
		
		wave = provider[wave_name]
		unless wave
			wave = Wave.new provider, wave_name, wave_domain
			provider << wave
		end
		
		data = data[:signed_delta] if data[:signed_delta] # remove extra stuff if it's an applied delta
		
		version = data[:delta][:applied_to][:version] + 1
		applied_to = wave[version - 1]
		
		unless applied_to
			applied_to = FakeDelta.new(wave)
			applied_to.version = version - 1
			applied_to.hash = data[:delta][:applied_to][:hash]
			wave << applied_to
		end
		
		return wave[version] if wave[version].is_a? Delta
		
		delta = Delta.new(wave, data[:delta][:author])
		delta.version = version
		data[:delta][:operations].each do |operation|
			type = operation.keys.first
			details = operation.values.first
			case type
				when :added
					delta.operations << AddUserOp.new(details)
				when :removed
					delta.operations << RemoveUserOp.new(details)
				when :mutate
					delta.operations << MutateOp.parse(details)
			end
		end
		
		wave << delta
		delta.propagate
		delta
	end
	
	# Dumps the raw delta to a hash. Not ready to send out, but used for
	# signing and hashing.
	def delta_hash
		{	:applied_to => prev_version,
			:author => @author,
			:operations => @operations.map{|op|op.to_hash}}
	end
	
	# Helper method to return a hash of the previous version/hash.
	def prev_version
		{	:version => @version - 1,
			:hash => prev_hash}
	end
	
	# Signs the +raw+ bytestring using the provider's key. TODO: Store the key
	# on the provider, not in Delta.
	def signature
		return @signature if @signature && @frozen
		@@private_key ||= OpenSSL::PKey::RSA.new(File.open("../danopia.net.key").read)
		@signature = @@private_key.sign OpenSSL::Digest::SHA1.new, raw
	end
	
	# Get a non-"applied delta", ready to send to a wave's master server.
	def to_s
		return @to_s if @to_s && @frozen
		@to_s = WaveProtoBuffer.encode(:signed_delta, {
			:delta => raw,
			:signature => {
				:signature => signature,
				:signer_id => @wave.provider.cert_hash,
				:signer_id_alg => 1 # 1 = RSA
			}
		})
	end
	
	# Get an "applied delta", ready to send out to others.
	def to_applied
		return @to_applied if @to_applied && @frozen
		@to_applied = WaveProtoBuffer.encode(:applied_delta, {
			:signed_delta => to_s,
			:applied_to => prev_version,
			:operations_applied => @operations.size, # operations applied
			:timestamp => @time.to_i * 1000 # milliseconds not needed yet
		})
	end
	
	# Find the previous version's hash. This is made simple because of FakeDelta.
	def prev_hash
		@wave[@version - 1].hash
	end
	
	# Hash the delta, using SHA2 and trimming down the length of SHA1.
	def hash
		return @hash if @hash && @frozen
		@hash = Digest::SHA2.digest("#{prev_hash}#{to_s}")[0,20]
	end
	
	# Freeze the delta for optimal speed once there aren't going to be any more
	# changes to it. Once frozen, each of +hash+, +to_s+, +signature+, and
	# +to_applied+ will only generate data once, and will cache it for future
	# calls.
	def freeze
		@frozen = true
		
		@hash = nil
		@to_s = nil
		@to_applied = nil
		@signature = nil
	end
	
	# Send the delta out to remote servers. Called by SailsRemote#add_delta and
	# Delta.parse.
	#
	# TODO: Handle each server better. (Queue, ping, etc.)
	def propagate
		people = wave.participants
		
		# Tell people who were removed (is this right?)
		@operations.each do |op|
			next unless op.is_a? RemoveUserOp
			people += op.who
		end
		
		# Make a list of servers to send to
		targets = []
		people.each do |person|
			person =~ /^.+@(.+)$/
			targets << $1 if $1
		end
		targets.uniq!
		
		# Don't send back to ourselfs
		targets.delete @wave.provider.name
		
		# Freeze and pre-render to make this faster, unless there's no targets
		freeze
		return if targets.empty?
		packet = "<request xmlns=\"urn:xmpp:receipts\"/><event xmlns=\"http://jabber.org/protocol/pubsub#event\"><items><item><wavelet-update xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" wavelet-name=\"#{@wave.conv_root_path}\"><applied-delta><![CDATA[#{encode64(self.to_s)}]]></applied-delta></wavelet-update></item></items></event>"
		
		p targets
		targets.uniq.each do |target|
			@wave.provider.sock.send_xml 'iq', 'get', target, '<query xmlns="http://jabber.org/protocol/disco#items"/>'
			sleep 5
			@wave.provider.sock.send_xml 'message', 'normal', 'wave.' + target, packet
		end
	end
end

# Represents a Wave, either local or remote.
class Wave
	attr_accessor :provider, :host, :name, :deltas#, :participants
	
	def initialize(provider, name=nil, host=nil)
		@provider = provider
		@name = name || provider.random_wave_name
		@host = host || provider.domain
		
		@deltas = {}
		#@participants = []
		
		self << FakeDelta.new(self)
	end
	
	# Returns a sorted list of all real deltas that this server has.
	def real_deltas
		@deltas.values.select{|delta| delta.is_a? Delta}.sort{|a, b| b.version <=> a.version}
	end
	
	# Makes a list of the wave's participants by looping through the deltas.
	#
	# Please don't call this more than you have to, since each call re-builds the
	# list.
	def participants
		participants = []
		
		real_deltas.reverse.each do |delta|
			delta.operations.each do |op|
				participants += op.who if op.is_a? AddUserOp
				participants -= op.who if op.is_a? RemoveUserOp
			end
		end
		
		participants
	end
	
	# Builds a wave path in the form of host/w+wave
	def path
		"#{@host}/w+#{@name}"
	end
	
	# Builds a wavelet path to 'conv+root' (for Fedone) in the form of
	# host/wave/conv+root
	def conv_root_path
		"#{path}/conv+root"
	end
	
	# Returns a certain delta, by version number.
	def [](version)
		@deltas[version]
	end
	
	# Adds a delta to the wave.
	def <<(delta)
		@deltas[delta.version] = delta
	end
	
	# Returns the latest version number. Faster than newest.version
	def newest_version
		@deltas.keys.sort.last
	end
	
	# Returns the latest Delta (according to version)
	def newest
		@deltas[@deltas.keys.sort.last]
	end
end
