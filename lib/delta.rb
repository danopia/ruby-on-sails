
module Sails

# Represents a version of a wavelet where the provider has details (as opposed
# to FakeDelta).
class Delta < BaseDelta
	attr_accessor :author, :time, :applied, :signature, :server, :signer_id, :commited, :record
	
	# Frozen deltas are considered to be unchanging, so the byte form is cached
	# to greatly speed up the creation of packets.
	attr_reader :frozen
	
	# Create a new delta. Defaults to applying itself to the latest delta from
	# the wave, but if you want to add older history in, you can override it with
	# version=. You should also try to set the time, if you can get it.
	def initialize wave, author=nil
		@wave = wave
		@version = wave.newest_version
		@time = Time.now.to_i * 1000
		@commited = false
		@frozen = false
		self.server = wave.provider.local
		
		@record = @wave.record.deltas.build :applied_to => @version,
			:version => @version,
			:server => @server.record,
			:signer_id => Utils.encode64(@signer_id)
			
		self.author = author if author # must be here to work with the record
		
		super wave, @version
	end
	
	def self.from_record wave, record
		data = Sails::ProtoBuffer.parse :delta, Utils.decode64(record.raw)
		
		delta = Delta.new wave, record.author
		delta.record = record
		delta.server = wave.provider.find_or_create_server record.server.domain
		delta.time = record.applied_at
		delta.signature = Utils.decode64 record.signature
		delta.version = data[:applied_to][:version]
		
		applied_to = wave[record.applied_to]
		unless applied_to
			applied_to = FakeDelta.new wave
			applied_to.version = record.applied_to
			applied_to.hash = data[:applied_to][:hash]
			wave << applied_to
		end
		
		unless delta.server
			wave.request_cert delta, delta.signer_id
		end
		
		data[:operations].each do |operation|
			type = operation.keys.first
			details = operation.values.first
			case type
				when :added
					delta << Operations::AddUser.new(details)
				when :removed
					delta << Operations::RemoveUser.new(details)
				when :mutate
					delta << Operations::Mutate.parse(details)
			end
		end
		
		delta.commited = true
		delta.freeze
		wave << delta
		
		delta
	end
	
	def server= server
		if server.is_a? String
			server = @wave.provider.servers[server]
		end
		
		@server = server
		@signer_id = server.certificate_hash if server
		
		if @record
			@record.signer_id = Utils.encode64 @signer_id
			@record.server = (@server.record rescue nil)
		end
		
		@signer_id
	end
	
	def local?
		@server == @wave.provider.local
	end
	
	def author=(author)
		author = "#{author.login}@#{@wave.provider.domain}" if author.is_a? User
		author = @wave.provider.find_or_create_user author unless author.is_a? WaveUser
		
		if @record
			@record.author = author.address
			@record.server = author.server.record
			@record.user = author.account
		end
		
		@author = author
	end
	
	def time=(stamp)
		@record.applied_at = stamp if @record
		
		@time = stamp
	end
	
	# Parses an incoming delta, taking the wavelet name (from the XML attribute)
	# and the bytestring (doesn't handle Base64). It will handle adding the delta
	# to a wave, creating the wave if it doesn't exist, and sending out the delta
	# to any other servers that need it. (TODO: Only do this when local delta)
	def self.parse provider, wavelet, data, applied=false
		timestamp = nil
		if applied
			data = Sails::ProtoBuffer.parse(:applied_delta, data) if data.is_a? String
			timestamp = data[:timestamp]
			data = data[:signed_delta]
		else
			data = Sails::ProtoBuffer.parse(:signed_delta, data) if data.is_a? String
		end
		
		wave = provider.find_or_create_wave wavelet
		wave.boom = true if wave.deltas.size == 1 && wave.local?
		
		delta = Delta.new(wave, data[:delta][:author])
		delta.version = data[:delta][:applied_to][:version]
		#delta.time = Time.at(timestamp / 1000) if timestamp
		delta.time = timestamp if timestamp
		delta.signature = data[:signature][:signature]
		
		delta.server = provider.servers.by_signer_id(data[:signature][:signer_id])
		delta.server ||= wave.server if wave.boom
		delta.signer_id = data[:signature][:signer_id]
		
		applied_to = delta.wave[delta.version]
		unless applied_to
			applied_to = FakeDelta.new(wave)
			applied_to.version = data[:delta][:applied_to][:version]
			applied_to.hash = data[:delta][:applied_to][:hash]
			wave << applied_to
		end
		
		unless delta.server
			wave.request_cert delta, delta.signer_id
		end
		
		data[:delta][:operations].each do |operation|
			type = operation.keys.first
			details = operation.values.first
			case type
				when :added
					delta << Operations::AddUser.new(details)
				when :removed
					delta << Operations::RemoveUser.new(details)
				when :mutate
					delta << Operations::Mutate.parse(details)
			end
		end
		
		if wave.boom
			puts "Sending back the delta as applied, even though the wave went boom."
			
			delta.server << ['message', 'normal', "<request xmlns=\"urn:xmpp:receipts\"/><event xmlns=\"http://jabber.org/protocol/pubsub#event\"><items><item><wavelet-update xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" wavelet-name=\"#{wave.conv_root_path}\"><applied-delta><![CDATA[#{Utils.encode64(delta.to_applied)}]]></applied-delta></wavelet-update></item></items></event>"]
			
			return delta
		end
		
		delta.commited = true if applied
		delta.freeze
		wave << delta
		
		delta
	end
	
	# Add an operation to the delta.
	def << operation
		@operations << operation
		
		@record.version = @version + 1 if @record
		
		@version += 1
	end
	
	# Dumps the raw delta to a hash. Not ready to send out, but used for
	# signing and building the full packets.
	def delta_data
		hash = {
			:applied_to => prev_version,
			:author => @author.to_s}
		hash[:operations] = @operations.map{|op|op.to_hash} if @operations.any?
		hash
	end
	
	# Dumps the raw delta to a ProtoBuffer string. Used for signing.
	def delta_raw
		Sails::ProtoBuffer.encode(:delta, delta_data)
	end
	
	# Helper method to return a hash of the previous version/hash.
	def prev_version
		{	:version => @version - @operations.size,
			:hash => prev_hash}
	end
	
	# Signs the +raw+ bytestring using the provider's key.
	def signature
		return @signature if @signature
		if @frozen
			@signature = @wave.provider.sign delta_raw
		else
			@wave.provider.sign delta_raw
		end
	end
	
	# Build a ProtoBuffer string of the delta in "non-applied" form, used to send
	# deltas to a wave's master server.
	def to_s
		return @to_s if @to_s && @frozen
		@to_s = Sails::ProtoBuffer.encode(:signed_delta, {
			:delta => delta_data,
			:signature => {
				:signature => signature,
				:signer_id => @signer_id,
				:signer_id_alg => 1 # 1 = RSA
			}
		})
	end
	
	# Get an "applied delta", ready to send out to slave servers.
	def to_applied
		return @to_applied if @to_applied && @frozen
		@to_applied = Sails::ProtoBuffer.encode(:applied_delta, {
			:signed_delta => to_s,
			:applied_to => prev_version,
			:operations_applied => @operations.size, # operations applied
			:timestamp => @time#.to_i * 1000 # milliseconds not needed yet
		})
	end
	
	# Find the previous version's hash. This is made simple because of FakeDelta.
	def prev_hash
		puts 'hi'
		puts "I am #{@version}"
		puts "looking at #{@version - @operations.size}"
		puts "(#{@wave[@version - @operations.size].version}," rescue nil
		puts "#{@wave[@version - @operations.size].class})"
		@wave[@version - @operations.size].hash
	end
	
	# Hash the delta, using SHA2 and trimming down the length of SHA1.
	def hash
		return @hash if @hash && @frozen
		@hash = Utils::sha2("#{prev_hash}#{to_applied}")[0,20]
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
		
		if @record
			@record.version = @version
			@record.applied_to = @version - @operations.size
			@record.raw = Utils.encode64 self.delta_raw
			@record.signature = Utils.encode64 self.signature
			@record.current_hash = Utils.encode64 self.hash
			@record.applied_at = self.time
			@record.save
		end
	end
	
	alias commited? commited
	
	# Send the delta out to remote servers. Called by SailsRemote#add_delta and
	# Delta.parse.
	def commit!
		return false if commited?
		@commited = true
		
		freeze
		wave.apply self

		if @wave.local?
			people = wave.participants
			
			# Tell people who were removed (is this right?)
			@operations.each do |op|
				next unless op.is_a? Operations::RemoveUser
				people += op.who
			end
			
			# Make a list of servers to send to
			targets = []
			people.each do |person|
				person.to_s =~ /^.+@(.+)$/
				targets << $1 if $1
			end
			targets.uniq!
			
			# Don't send back to ourself
			targets.delete @wave.provider.domain
			
			unless targets.empty?
			
				packet = "<request xmlns=\"urn:xmpp:receipts\"/><event xmlns=\"http://jabber.org/protocol/pubsub#event\"><items><item><wavelet-update xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" wavelet-name=\"#{@wave.conv_root_path}\"><applied-delta><![CDATA[#{Utils.encode64(to_applied)}]]></applied-delta></wavelet-update></item></items></event>"
				
				puts "Sending to #{targets.join(', ')}"
				
				targets.uniq.each do |target|
					server = @wave.provider.find_or_create_server target
					puts "Handing off a packet for #{server.name}"
					server << ['message', 'normal', packet]
				end
			end
	
		else # Then it's remote; send out the request
			if local?
				@wave.server << ['iq', 'set', "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish node=\"wavelet\"><item><submit-request xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"><delta wavelet-name=\"#{@wave.conv_root_path}\"><![CDATA[#{encode64(to_s)}]]></delta></submit-request></item></publish></pubsub>"]
			end
		end
		
		#if @wave.participants.include?('echoey@danopia.net') && @author != 'echoey@danopia.net'
			#puts 'poking Echoey'
			#Echoey.new.handle $remote, @wave, @operations.select {|op| op.is_a? Operations::Mutate }.map {|op| @wave.blip(op.document_id) }.uniq.first
		#end
	end
	
end # class

end # module
