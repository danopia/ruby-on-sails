

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
		@hash = hash || "#{wave.conv_root_path}"
	end
	
	# Easier than adding more if's
	def operations
		[:noop]
	end
end

# Represents a version of a wavelet where the provider has details (as opposed
# to FakeDelta).
class Delta
	attr_accessor :wave, :version, :author, :operations, :time, :applied, :signature, :signer_id
	
	# Frozen deltas are considered to be unchanging, so the byte form is cached
	# to greatly speed up the creation of packets.
	attr_reader :frozen
	
	# Create a new delta. Defaults to applying itself to the latest delta from
	# the wave, but if you want to add older history in, you can override it with
	# version=. You should also try to set the time, if you can get it.
	def initialize(wave, author=nil)
		@wave = wave
		@author = author
		@version = wave.newest_version #+ 1
		@operations = []
		@time = Time.now.to_i * 1000
		@applied = false
		@frozen = false
		@signer_id = wave.provider.local.certificate_hash
	end
	
	# Parses an incoming delta, taking the wavelet name (from the XML attribute)
	# and the bytestring (doesn't handle Base64). It will handle adding the delta
	# to a wave, creating the wave if it doesn't exist, and sending out the delta
	# to any other servers that need it. (TODO: Only do this when local delta)
	def self.parse provider, wavelet, data, applied=false
		timestamp = nil
		if applied
			data = WaveProtoBuffer.parse(:applied_delta, data) if data.is_a? String
			timestamp = data[:timestamp]
			data = data[:signed_delta]
		else
			data = WaveProtoBuffer.parse(:signed_delta, data) if data.is_a? String
		end
		
		wavelet.sub! 'wave://', ''
		wavelet =~ /^(.+)\/w\+(.+)\/(.+)$/
		wave_domain, wave_name, wavelet_name = $1, $2, $3
		puts "Parsing #{wave_domain}'s #{wavelet_name} wavelet for w+#{wave_name}"
		
		wave = provider[wave_name]
		unless wave
			wave = Wave.new provider, wave_name, wave_domain
			provider << wave
		end
		
		version = data[:delta][:applied_to][:version]
		applied_to = wave[version]
		
		unless applied_to
			applied_to = FakeDelta.new(wave)
			applied_to.version = version
			applied_to.hash = data[:delta][:applied_to][:hash]
			wave << applied_to
		end
		
		#return wave[version] if wave[version].is_a? Delta
		
		delta = Delta.new(wave, data[:delta][:author])
		delta.version = version
		#delta.time = Time.at(timestamp / 1000) if timestamp
		delta.time = timestamp if timestamp
		delta.signature = data[:signature][:signature]
		delta.signer_id = data[:signature][:signer_id]
		
		data[:delta][:operations].each do |operation|
			type = operation.keys.first
			details = operation.values.first
			case type
				when :added
					delta << AddUserOp.new(details)
				when :removed
					delta << RemoveUserOp.new(details)
				when :mutate
					delta << MutateOp.parse(details)
			end
		end
		
		wave << delta
		
		delta.propagate(applied) unless applied
		
		delta
	end
	
	def <<(operation)
		@operations << operation
		@version += 1
	end
	
	# Dumps the raw delta to a hash. Not ready to send out, but used for
	# signing and hashing.
	def delta_data
		{	:applied_to => prev_version,
			:author => @author,
			:operations => @operations.map{|op|op.to_hash}}
	end
	
	def delta_raw
		WaveProtoBuffer.encode(:delta, delta_data)
	end
	
	# Helper method to return a hash of the previous version/hash.
	def prev_version
		{	:version => @version - @operations.size,
			:hash => prev_hash}
	end
	
	# Signs the +raw+ bytestring using the provider's key. TODO: Store the key
	# on the provider, not in Delta.
	def signature
		return @signature if @signature
		if @frozen
			return @signature = @wave.provider.sign(delta_raw)
		else
			return @wave.provider.sign(delta_raw)
		end
	end
	
	# Get a non-"applied delta", ready to send to a wave's master server.
	def to_s
		return @to_s if @to_s && @frozen
		@to_s = WaveProtoBuffer.encode(:signed_delta, {
			:delta => delta_data,
			:signature => {
				:signature => signature,
				:signer_id => @signer_id,
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
			:timestamp => @time#.to_i * 1000 # milliseconds not needed yet
		})
	end
	
	# Find the previous version's hash. This is made simple because of FakeDelta.
	def prev_hash
		@wave[@version - @operations.size].hash
	end
	
	# Hash the delta, using SHA2 and trimming down the length of SHA1.
	def hash
		return @hash if @hash && @frozen
		@hash = Digest::SHA2.digest("#{prev_hash}#{to_applied}")[0,20]
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
		#@signature = nil
	end
	
	# Send the delta out to remote servers. Called by SailsRemote#add_delta and
	# Delta.parse.
	#
	# TODO: Handle each server better. (Queue, ping, etc.)
	def propagate applied=false
		if @wave.local?
			wave.playback.apply self
			
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
			p targets
			targets.delete @wave.provider.domain
			targets.delete 'danopia.net' if @wave.provider.domain == 'wave.danopia.net'
			p targets
			
			# Freeze and pre-render to make this faster, unless there's no targets
			freeze
			return if targets.empty?
			
			packet = "<request xmlns=\"urn:xmpp:receipts\"/><event xmlns=\"http://jabber.org/protocol/pubsub#event\"><items><item><wavelet-update xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" wavelet-name=\"#{@wave.conv_root_path}\"><applied-delta><![CDATA[#{encode64(self.to_applied)}]]></applied-delta></wavelet-update></item></items></event>"
			
			puts "Sending to #{targets.join(', ')}"
			
			targets.uniq.each do |target|
				server = @wave.provider.servers[target.downcase]
				
				unless server
					server = Server.new @wave.provider, target.downcase
					@wave.provider << server
				end
				
				puts "Handing off a packet for #{server.name}"
				server << ['message', 'normal', packet]
			end
	
		else # Then it's remote; send out the request
			freeze
			@wave.provider.servers[@wave.host] << ['iq', 'set', 
				"<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish node=\"wavelet\"><item><submit-request xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"><delta wavelet-name=\"#{@wave.conv_root_path}\"><![CDATA[#{encode64(self.to_s)}]]></delta></submit-request></item></publish></pubsub>"]
			puts "Queued a packet for #{@wave.host}"
		end
	end
	
	def encode64(data)
		Base64.encode64(data).gsub("\n", '')
	end
	def decode64(data)
		Base64.decode64(data)
	end
end

