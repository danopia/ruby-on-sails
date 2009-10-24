#require 'openssl'
require 'drb'

class SailsRemote
	attr_accessor :drb, :provider
	
	def self.serve(provider, host=':9000')
		remote = SailsRemote.new(provider)
		remote.drb = DRb.start_service("druby://#{host}", remote)
		remote
	end
	def self.connect(host=':9000')
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
	attr_accessor :certs, :cert_hash, :domain, :name, :waves
	
	def initialize(domain, subdomain='wave')
		@certs = {}
		@cert_hash = nil
		@domain = domain
		@name = "#{subdomain}.#{domain}"
		@waves = {}
		
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
	attr_accessor :wave, :version, :author, :operations
	
	def initialize(wave, author=nil)
		@wave = wave
		@author = author
		@version = wave.newest_version + 1
		@operations = []
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
		pp data
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
		
		#{0=>
			#[{0=>
				 #[{0=>
						#[{0=>[1],
							#1=>["\340\003\023yt\3001\346\vZ\212\220\a\222_n\371\024= "]}],
					 #1=>["kevin@killerswan.com"],
					 #2=>[{0=>["danopia@danopia.net"]}]}],
				#1=>
				 #[{0=>
						#["Q\206\335\343\215\216D\330u'\020\331\327\325.ex\347y5\023\227\236\r\034\222\202\273\000E\263<\340<\357\2643\266\347y\206\235\256\311\234\026\205{\367\206\327\333 f\305\343M/B\315\215e\216\350G\177P'\333\335\r\360\337\332\354\354\n\026\206\037\335\306\023\303\037N3\205e\210\367_\240\311!U\252]\307\333>\235\207\242\267\202\2532\022\"\260H\227MF\314\005X\377Pp\226\177d\347\035\027}"],
					 #1=>
						#["\e\302\b\236\356\276\316\322Z\325\221e\e\001\357i[\21345\223%}l\322\334\230\234\220\351m\241"],
					 #2=>[1]}]}],
		 #1=>[{0=>[1], 1=>["\340\003\023yt\3001\346\vZ\212\220\a\222_n\371\024= "]}],
		 #2=>[1],
		 #3=>[1256114214507]}
		 delta
	end
	
	def raw
		ProtoBuffer.encode({
			0 => {
				0 => @version - 1,
				1 => prev_hash
			},
			1 => @author,
			2 => @operations.map{|op|op.to_hash}
		})
	end
	
	def signature
		@@private_key ||= OpenSSL::PKey::RSA.new(File.open("../danopia.net.key").read)
		@@private_key.sign OpenSSL::Digest::SHA1.new, raw
	end
	
	def to_s
		ProtoBuffer.encode({
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
			3 => Time.now.to_i * 1000 # milliseconds not needed yet
		})
	end
	
	def prev_hash
		@wave[@version - 1].hash
	end
	
	def hash
		@hash = Digest::SHA2.digest("#{prev_hash}#{raw}")[0,20]
	end
	
	def propagate
		
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
