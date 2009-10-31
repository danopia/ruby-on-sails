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
	
	# Returns a list of waves from all servers
	def all_waves
		waves = []
		waves += @provider.waves.values
		@provider.servers.each_value do |server|
			waves += server.waves.values
		end
		waves
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


# Represents a server, remote or local, and tracks certificates, waves, and the
# queue of packets to send to a server once a connection is established.
class Server
	attr_accessor :provider, :certificate, :certificate_hash, :domain, :name, :waves, :queue, :state
	
	# Create a new server.
	def initialize(provider, domain, name=nil)
		@provider = provider
		@certificate = nil
		@certificate_hash = nil
		@domain = domain
		@name = name || domain
		@waves = {}
		@queue = []
		@state = :uninited
	end
	
	# Sets the certificate and generates a SHA2 hash in ASN.1/DER format, ready
	# to send to remote servers.
	def certificate=(certificate)
		@certificate = certificate
		@certificate_hash = Digest::SHA2.digest "0\202\003\254#{decode64(@certificate)}"
		p @certificate_hash
	end
	
	def name=(new_name)
		@provider.servers.delete @name.downcase unless !@name || @name == @domain
		@provider.servers[new_name.downcase] = self
		
		@name = new_name
	end
	
	# Return a wave.
	#
	# Must be passed only the name, i.e. you must pass "w+meep" to get meep. No
	# domains will be handled.
	def [](name)
		return @waves[name] if @waves.has_key?(name)
	end
	
	# Add a wave to the server's listing -or- queue/send a packet.
	def <<(item)
		if item.is_a? Array # packet
			if @state == :ready
				@provider.sock.send_xml item[0], item[1], @name, item[2], item[3]
			else
				@queue << item
			end
			
		elsif item.is_a? Wave
			@waves[item.name] = item
			
		else
			0/0 # Yay for error handling
		end
	end
	
	# Send the queue out (state must be :ready)
	def flush
		return false unless @state == :ready && @provider.state == :ready
		return nil unless @queue && @queue.any?
		
		@queue.each do |packet|
			@provider.sock.send_xml packet[0], packet[1], @name, packet[2], packet[3]
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
end

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
end

# Most popular class. Represents the local server and the waves on it, and
# keeps a list of external servers.
class Provider < Server
	attr_accessor :sock, :servers
	
	# Create a new provider.
	def initialize(domain, subdomain='wave')
		subdomain = "#{subdomain}." if subdomain
		puts domain
		puts "#{subdomain}#{domain}"
		super self, domain, "#{subdomain}#{domain}"
		
		
		@sock = nil
		@servers = ServerList.new
		
		self.certificate = open("#{@domain}.cert").read.split("\n")[1..-2].join('')
	end
	
	# Return a wave.
	#
	# Can be passed in domain/w+name format for a certain wave, or name format
	# to search all known waves.
	def [](name)
		if name =~ /^(.+)\/w\+(.+)$/
			server = @servers[$1.downcase]
			return nil unless server
			server[$2]
		else
			# allow fallback to not specifing a domain, but search self first
			return @waves[name] if @waves[name]
			
			@servers.values.each do |server|
				wave = server[name]
				return wave if wave
			end
			
			nil
		end
	end
	
	# Add a wave to the main listing -or- Add a server to the main list
	def <<(item)
		if item.is_a? Server
			@servers[item.domain] = item
			init_server item if @state == :ready
		
		elsif item.is_a? Wave
			server = @servers[item.host]
			unless server
				server = Server.new(self, item.host, item.host)
				self << server
			end
			server << item
			
		else
			0/0 # Yay for error handling
		end
	end
	
	# Init a Server connection by pinging it and sending a cert. Called for you
	# if/when you << the Server to the Provider.
	def init_server server
		return unless @state == :ready
		@sock.send_xml 'iq', 'get', server.name || server.domain,
			'<query xmlns="http://jabber.org/protocol/disco#items"/>'
		server.state = :sent_item_request
	end
	
	# Flush all the remote servers.
	def flush
		return unless @state == :ready
		
		@servers.each_value do |server|
			if server.state == :uninited
				@sock.send_xml 'iq', 'get', server.name || server.domain,
					'<query xmlns="http://jabber.org/protocol/disco#items"/>'
				server.state = :sent_item_request
			else
				server.flush
			end
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
		@version = wave.newest_version + 1
		@operations = []
		@time = Time.now.to_i * 1000
		@applied = false
		@frozen = false
		@signer_id = wave.provider.certificate_hash
		puts 'a'
		p @signer_id
	end
	
	# Parses an incoming delta, taking the wavelet name (from the XML attribute)
	# and the bytestring (doesn't handle Base64). It will handle adding the delta
	# to a wave, creating the wave if it doesn't exist, and sending out the delta
	# to any other servers that need it. (TODO: Only do this when local delta)
	def self.parse provider, wavelet, data, applied=false
		timestamp = nil
		if applied
			p data
			data = WaveProtoBuffer.parse(:applied_delta, data) if data.is_a? String
			p data
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
		
		version = data[:delta][:applied_to][:version] + 1
		applied_to = wave[version - 1]
		
		unless applied_to
			applied_to = FakeDelta.new(wave)
			applied_to.version = version - 1
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
					delta.operations << AddUserOp.new(details)
				when :removed
					delta.operations << RemoveUserOp.new(details)
				when :mutate
					delta.operations << MutateOp.parse(details)
			end
		end
			p delta.to_applied
		
		wave << delta
		if applied
			wave.apply delta
		else
			delta.propagate(applied)
		end
		
		delta
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
		{	:version => @version - 1,
			:hash => prev_hash}
	end
	
	# Signs the +raw+ bytestring using the provider's key. TODO: Store the key
	# on the provider, not in Delta.
	def signature
		return @signature if @signature
		@@private_key ||= OpenSSL::PKey::RSA.new(File.open("#{@wave.provider.domain}.key").read)
		if @frozen
			return @signature = @@private_key.sign(OpenSSL::Digest::SHA1.new, delta_raw)
		else
			return @@private_key.sign(OpenSSL::Digest::SHA1.new, delta_raw)
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
		@wave[@version - 1].hash
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
			wave.apply self
			
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

# Represents a Wave, either local or remote.
class Wave
	attr_accessor :provider, :host, :name, :deltas, :participants, :contents, :applied_to
	
	def initialize(provider, name=nil, host=nil)
		@provider = provider
		@name = name || provider.random_wave_name
		@host = host || provider.domain
		
		@deltas = {}
		@participants = []
		@contents = []
		@applied_to = 0
		
		self << FakeDelta.new(self)
	end
	
	# Size of the wave's contents, strings are the number of bytes and everything
	# else counts as one
	def item_count
		@contents.inject(0) do |total, item|
			if item.is_a? String
				next total + item.size
			else
				next total + 1
			end
		end
	end
	
	# Returns a sorted list of all real deltas that this server has.
	def real_deltas
		@deltas.values.select{|delta| delta.is_a? Delta}.sort{|a, b| b.version <=> a.version}
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
	
	# Is the wave local?
	def local?
		@host == @provider.domain
	end
	
	# Determines if the wave has a complete history
	#
	# Pass true as the argument to request more history if incomplete; pass a
	# Hash and it'll set key packet-id to the current Wave.
	def complete?(request_more=false)
		@deltas.each_value do |delta|
			if delta.is_a?(FakeDelta) && delta.version != 0
			
				if request_more
					puts "Requesting more deltas for #{self.path}"
					
					server = @provider.servers[@host]
					unless server
						server = Server.new(@provider, @host, @host)
						@provider << server
					end
					
					id = @provider.sock.rand_id
					server << ['iq', 'get', "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items node=\"wavelet\"><delta-history xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" start-version=\"0\" start-version-hash=\"#{encode64(self[0].hash)}\" end-version=\"#{self.newest_version}\" end-version-hash=\"#{encode64(self.newest.hash)}\" wavelet-name=\"#{self.conv_root_path}\"/></items></pubsub>", id]
					request_more[id] = self if request_more.is_a? Hash
				end
				
				return false
			end
		end
		true
	end
	
	def apply(delta=nil)
		delta ||= self[@applied_to + 1]
		#pp delta
		#pp self
		if !complete?
			puts "The wave isn't complete; I can't apply a delta yet."
		elsif delta.applied
			puts "That delta is already applied."
		else
			if (delta.version - 1) > @applied_to
				puts "Need to apply #{delta.version - @applied_to - 1} deltas first."
				apply until @applied_to == delta.version - 1
			end
			
			puts "Applying delta #{delta.version} to #{self.path}"
			
			delta.operations.each do |op|
				@participants += op.who if op.is_a? AddUserOp
				@participants -= op.who if op.is_a? RemoveUserOp
				apply_mutate(op) if op.is_a? MutateOp
			end
			
			@applied_to += 1
			delta.applied = true
		end
	end
	
	protected
	
	# Apply a mutation. Does NO version checking!
	#
	# TODO: Handle mid-string stuff. Might add a whole class for mutations.
	def apply_mutate(operation)
		if operation.document_id != 'main'
			puts "Non-main document: #{document}. ABORT"
			p operation
			exit
		end
		
		item = 0 # in the 'contents' array
		index = 0 # in a string
		operation.components.each do |component|
			if component[:retain_item_count]
				advance = component[:retain_item_count]
				until advance == 0
					if !@contents[item].is_a?(String)
						advance -= 1
						item += 1
						index = 0
					elsif (@contents[item].size - index) <= advance
						advance -= (@contents[item].size - index)
						item += 1
						index = 0
					else # advance within current string
						index += advance
						advance = 0
					end
				end
				puts "Advanced #{component[:retain_item_count]} items"
			
			elsif component[:element_start]
				element = Element.new(component[:element_start][:type])
				component[:element_start][:attributes].each do |attribute|
					element.attributes[attribute[:key]] = attribute[:value]
				end
				
				@contents.insert(item, element)
				item += 1
				index = 0
			
			elsif component[:element_end]
				@contents.insert(item, :end)
				item += 1
				index = 0
			
			elsif component[:characters]
				@contents.insert(item, component[:characters])
				item += 1
				index = 0
			end
		end
	end
end

class Element
	attr_accessor :type, :attributes
	def initialize(type=nil)
		@type = type
		@attributes = {}
	end
end
