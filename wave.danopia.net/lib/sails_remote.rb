#require 'openssl'
require 'drb'

class SailsRemote
	attr_accessor :drb, :provider
	
	def self.serve(provider, host=':9001')
		remote = SailsRemote.new(provider)
		remote.drb = DRb.start_service("druby://#{host}", remote)
		remote
	end
	def self.connect(host=':9001')
		DRbObject.new nil, "druby://#{host}"
	end
	
	def initialize(provider)
		@provider = provider
		@drb = nil
	end
	
	def uri
		@drb.uri if @drb
	end
	def stop_service
		@drb.stop_service if @drb
	end
	
	def waves
		@provider.waves
	end
	
	def [](name)
		@provider[name]
	end
	def <<(wave)
		@provider << wave
	end
	
	def add_delta(wave, delta)
		if wave.is_a? Wave
			wave << delta# unless wave.deltas.include?(delta)
			wave = wave.name
		end
		self[wave] << delta
		delta.propagate
	end
	
	def random_name(length=12)
		chars = ''
		@@letters ||= ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
		length.times do
			chars << @@letters[rand * @@letters.size]
		end
		chars
	end
end


class Provider
	attr_accessor :certs, :cert_hash, :domain, :name, :waves, :sock
	
	def initialize(domain, subdomain='wave')
		@certs = {}
		@cert_hash = nil
		@domain = domain
		@name = "#{subdomain}.#{domain}"
		@waves = {}
		@sock = nil
		
		@certs[domain] = open("#{domain}.cert").read.split("\n")[1..-2].join('')
	end
	
	def cert_hash
		return @cert_hash if @cert_hash
		@cert_hash = decode64(@certs[@domain])
		@cert_hash = Digest::SHA2.digest "0\202\003\254#{@cert_hash}"
	end
	
	def [](name)
		return @waves[name] if @waves.has_key?(name)
		
		# allow fallback to not specifing a domain
		waves = @waves.values.select{|wave|wave.name == name}
		return nil if waves.empty?
		waves.first
	end
	
	def <<(wave)
		@waves[wave.path] = wave
	end
end


class FakeDelta
	attr_accessor :wave, :version, :hash
	
	def initialize(wave)
		@wave = wave
		@version = 0
		@hash = "wave://#{wave.conv_root_path}"
	end
end

class AddUserOp
	attr_accessor :who
	
	def initialize(who)
		who = [who] unless who.is_a? Array
		@who = who
	end
	
	def to_hash
		{0 => @who}
	end
	
	def to_s
		"Added #{@who.join(', ')} to the wave"
	end
end

class RemoveUserOp
	attr_accessor :who
	
	def initialize(who)
		who = [who] unless who.is_a? Array
		@who = who
	end
	
	def to_hash
		{1 => @who}
	end
	
	def to_s
		"Removed #{@who.join(', ')} from the wave"
	end
end

class MutateOp
	attr_accessor :document_id, :operations
	
	def initialize(document_id=nil, operations=[])
		operations = [operations] unless operations.is_a? Array
		
		@document_id = document_id
		@operations = operations
	end
	
	def self.parse(hashes)
		doc = hashes[0].first
		operations = hashes[1].first[0]
		MutateOp.new(doc, operations)
	end
	
	def to_hash
		#{2=>{2=>{0=>"main",1=> {0=>["(\004",
		#	{2=>{0=>"line", 1=>{0=>"by", 1=>author}}}," \001",
		#	{1=>text}]}}}}
		{2 =>
			{0 => @document_id,
			 1 => {0 => operations}}}
	end
	
	def to_s
		operations.last[1]
	end
end

class Delta
	attr_accessor :wave, :version, :author, :operations, :time
	attr_reader :frozen
	
	def initialize(wave, author=nil)
		@wave = wave
		@author = author
		@version = wave.newest_version + 1
		@operations = []
		@time = Time.now
		@frozen = false
	end
	
	def self.parse provider, wavelet, data
		data = ProtoBuffer.parse data if data.is_a? String
		
		wavelet =~ /^(.+)\/w\+(.+)\/(.+)$/
		wave_domain, wave_name, wavelet_name = $1, $2, $3
		puts "Parsing #{wave_domain}'s #{wavelet_name} wavelet for w+#{wave_name}"
		
		wave = provider[wave_name]
		unless wave
			wave = Wave.new provider, wave_name, wave_domain
			provider << wave
		end
		
		data = data[0].first unless data.size < 4 # remove extra stuff if it's an applied delta
		#pp data
		version = data[0].first[0].first[0].first + 1
		applied_to = wave[version - 1]
		
		unless applied_to
			applied_to = FakeDelta.new(wave)
			applied_to.version = version - 1
			applied_to.hash = data[0].first[0].first[1].first
			wave << applied_to
		end
		
		return wave[version] if wave[version].is_a? Delta
		
		delta = Delta.new(wave, data[0].first[1].first)
		delta.version = version
		data[0].first[2].first.each_pair do |type, ops|
			ops.each do |args|
				case type
					when 0
						delta.operations << AddUserOp.new(args)
					when 1
						delta.operations << AddUserOp.new(args)
					when 2
						delta.operations << MutateOp.parse(args)
				end
			end
		end
		
		wave << delta
		delta.propagate
		delta
	end
	
	def raw
		return @raw if @raw && @frozen
		@raw = ProtoBuffer.encode({
			0 => {
				0 => @version - 1,
				1 => prev_hash
			},
			1 => @author,
			2 => @operations.map{|op|op.to_hash}
		})
	end
	
	def signature
		return @signature if @signature && @frozen
		@@private_key ||= OpenSSL::PKey::RSA.new(File.open("../danopia.net.key").read)
		@signature = @@private_key.sign OpenSSL::Digest::SHA1.new, raw
	end
	
	def to_s
		return @to_s if @to_s && @frozen
		@to_s = ProtoBuffer.encode({
			0 => {
				0 => raw,
				1 => {
					0 => signature,
					1 => @wave.provider.cert_hash,
					2 => 1 # alg (rsa)
				}
			},
			1 => {
				0 => @version - 1,
				1 => prev_hash
			},
			2 => @operations.size, # operations applied
			3 => @time.to_i * 1000 # milliseconds not needed yet
		})
	end
	
	def prev_hash
		@wave[@version - 1].hash
	end
	
	def hash
		return @hash if @hash && @frozen
		@hash = Digest::SHA2.digest("#{prev_hash}#{to_s}")[0,20]
	end
	
	
	def freeze
		@frozen = true
		
		@hash = nil
		@to_s = nil
		@signature = nil
		@raw = nil
	end
	
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
		
		# But we do ignore ourself
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

class Wave
	attr_accessor :provider, :host, :name, :deltas, :participants
	
	def initialize(provider, name, host=nil)
		@provider = provider
		@name = name
		@host = host || provider.domain
		
		@deltas = {}
		@participants = []
		
		self << FakeDelta.new(self)
	end
	
	def real_deltas
		@deltas.values.select{|delta| delta.is_a? Delta}.sort{|a, b| b.version <=> a.version}
	end
	
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
	
	def path
		"#{@host}/w+#{@name}"
	end
	
	def conv_root_path
		"#{path}/conv+root"
	end
	
	def [](version)
		@deltas[version]
	end
	
	def <<(delta)
		@deltas[delta.version] = delta
	end
	
	def newest_version
		@deltas.keys.sort.last
	end
	def newest
		@deltas[@deltas.keys.sort.last]
	end
end
