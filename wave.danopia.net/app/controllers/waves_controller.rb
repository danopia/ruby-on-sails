require 'socket'
require 'digest/sha1'
require 'digest/sha2'

require 'rubygems'
require 'hpricot'

require 'stringio'
require 'base64'
require 'pp'
require 'openssl'
require 'drb'

def encode64(data)
	Base64.encode64(data).gsub("\n", '')
end
def decode64(data)
	Base64.decode64(data)
end

class ProtoBuffer
	def self.parse(data)
		data = StringIO.new(data)
		
		puts "Parsing #{data.string.inspect}"
		
		hash = {}
		parse_args hash, data, [] until data.eof?
		
		#puts "Done."
		#pp hash
		
		hash
	end
	
	def self.parse_args(parent_args, data, tree)
		key = data.getc
		type = key % 8
		key = (key / 8) - 1
		
		value = -1
		
		if type == 0 # Varint
			value = read_varint(data)
			#puts "#{'  '*(tree.size+1)}#{key} => int: #{value}"
		
		elsif type == 2 # Fixed-width (e.g. strings)
			value = {}
			raw = StringIO.new(read_string(data))
			#puts "#{'  '*tree.size}Parsing \##{key}. Tree: #{tree.join(' -> ')} Data: #{raw.string.inspect}"
			
			if (1..8).to_a.map{|num|(2+num*8)}.include?(raw.string[0]) || raw.string[0] == 8
				parse_args value, raw, tree + [key] until raw.eof?
			else
				#puts "#{'  '*tree.size}String: #{raw.string.inspect}"
				value = raw.string
			end
		
		else
			puts "Unknown type: #{type}"
		end
		
		parent_args[key] ||= []
		parent_args[key] << value
	end
	
	def self.read_varint(io)
		index = 0
		value = 0
		while true
			byte = io.getc
			if byte & 0x80 > 0
				value |= (byte & 0x7F) << index
				index += 7
			else
				return value | byte << index
			end
		end
	end
	def self.read_string(io)
		io.read read_varint(io)
	end

	def self.write_varint(value)
		bytes = ''
		while value > 0x7F
			bytes << ((value & 0x7F) | 0x80).chr
			value >>= 7
		end
		bytes << value.chr
	end
	def self.write_string(io, string)
		io << write_varint(string.size) << string
	end
	
	def self.encode(hash)
		output = ''
		hash.each_pair do |type, value|
			value = [value] unless value.is_a? Array
			value.each do |arg|
				if arg.is_a? Hash
					output << (type*8+10).chr
					write_string output, encode(arg)
				elsif arg.is_a?(Fixnum) || arg.is_a?(Bignum)
					output << (type*8+8).chr
					output << write_varint(arg)
				else
					output << (type*8+10).chr
					write_string output, arg
				end
			end
		end
		output
	end
end

class FakeDelta
	attr_accessor :wave, :version, :hash
	
	def initialize(wave)
		@wave = wave
		@version = 0
		@hash = wave.conv_root_path
	end
end

class Delta
	attr_accessor :applied_to, :wave, :author, :version, :operations
	
	def initialize(wave)
		@applied_to = wave.deltas.last
		@wave = wave
		@author = nil
		@hash = nil
		@version = @applied_to.version + 1
		@operations = []
	end
	
	def self.parse wavelet, data
		data = ProtoBuffer.parse data if data.is_a? String
		
		wavelet =~ /^(.+)\/w\+(.+)\/(.+)$/
		wave_domain, wave_name, wavelet_name = $1, $2, $3
		puts "Parsing #{wave_domain}'s #{wavelet_name} wavelet for w+#{wave_name}"
		
		wave = Wave.find wave_name
		unless wave
			wave = Wave.new wave_domain, wave_name
			Wave.waves << wave
		end
		
		data = data[0].first unless data.size < 4 # remove extra stuff if it's an applied delta
		pp data
		applied_to = data[0].first[0].first[0].first
		version = applied_to + 1
		applied_to = wave.get_delta(applied_to)
		unless applied_to
			applied_to = FakeDelta.new(wave)
			applied_to.version = data[0].first[0].first[0].first
			applied_to.hash = data[0].first[0].first[1].first
		end
		
		return if wave.get_delta(version).is_a? Delta
		
		delta_data = data[0].first
		delta = Delta.new(wave)
		delta.applied_to = applied_to
		delta.version = applied_to.version + 1
		delta.author = delta_data[1].first
		delta.operations = delta_data[2]
		
		wave.deltas << delta
		
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
				0 => @applied_to.version,
				1 => @applied_to.hash
			},
			1 => @author,
			2 => @operations
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
					1 => "J\207\315\203\267:Vu\204\216\224\004[.\t(\3670\002\374\3045{7\365\304`qX\030w\305",
					2 => 1 # alg (rsa)
				}
			},
			1 => {
				0 => @applied_to.version, # previous version
				1 => @applied_to.hash # previous hash
			},
			2 => @operations.size, # operations applied
			3 => Time.now.to_i * 1000 # milliseconds not needed yet
		})#[1..-1]
	end
	
	def hash
		@hash = Digest::SHA2.digest("#{@applied_to.hash}#{raw}")[0,20]
	end
	
	def propagate
		
	end
end

class Wave
	attr_accessor :deltas, :host, :name, :participants
	
	def real_deltas
		@deltas.select do |delta|
			delta.is_a? Delta
		end
	end
	
	def participants
		@participants = []
		
		real_deltas.each do |delta|
			delta.operations.each do |operation|
				@participants << delta.operations.first[0] if delta.operations.first[0]
				@participants.delete delta.operations.first[1] if delta.operations.first[1]
			end
		end
		
		@participants
	end
	
	def self.waves
		@waves ||= []
	end
	
	def initialize(host, name)
		@host = host
		@name = name
		@participants = []
		
		@deltas = [FakeDelta.new(self)]
	end
	
	def conv_root_path
		"wave://#{host}/w+#{name}/conv+root"
	end
	
	def conv_root_path2
		"#{host}/w+#{name}/conv+root"
	end
	
	def new_delta(author=nil)
		delta = Delta.new self
		delta.author = author
		@deltas << delta
		delta
	end
	
	def self.find(name)
		return nil unless name
		
		@waves ||= []
		waves = @waves.select{|wave| wave.name == name}
		return nil if waves.empty?
		waves.first
	end
	
	def get_delta(version)
		return nil unless version
		
		deltas = @deltas.select{|delta| delta.version == version}
		return nil if deltas.empty?
		deltas.first
	end
end













class WavesController < ApplicationController
	before_filter :require_user

  def index
		@address = "#{current_user.login}@danopia.net"
		
		server = DRbObject.new nil, 'druby://:9000'
		@waves = server.waves
  end

  def show
		@address = "#{current_user.login}@danopia.net"
		
		server = DRbObject.new nil, 'druby://:9000'
		
		if params[:id] == 'new'
			@wave = Wave.new('danopia.net', random_name)
			server.add_wave @wave
    	redirect_to wave_path(@wave.name)
			return
		end
		
		@wave = server.find params[:id]
		
		unless @wave.participants.include? @address
			delta = @wave.new_delta @address
			delta.operations << {0 => @address}
    	server.add_delta @wave.name, delta
			
			#delta = @wave.new_delta @address
			#delta.operations << create_text_mutate(@address, "Hey there, this is #{@address}, and I'm using Ruby on Sails!")
    	#server.add_delta @wave.name, delta
    end
    
  end

  def update
		@address = "#{current_user.login}@danopia.net"
		
		server = DRbObject.new nil, 'druby://:9000'
		@wave = server.find params[:id]
		
		if @wave.participants.include? @address
			delta = @wave.new_delta @address
			delta.operations << create_text_mutate(@address, params[:message])
    	server.add_delta @wave.name, delta
    end
    
    redirect_to wave_path(@wave.name) + '#r' + delta.version.to_s
  end

	protected
	
	def random_name
		chars = ''
		letters = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
		12.times do
			chars << letters[rand * letters.size]
		end
		chars
	end
	
	def create_text_mutate(author, text)
		{2=>{2=>{0=>"main",1=> {0=>["(\004",
			{2=>{0=>"line", 1=>{0=>"by", 1=>author}}}," \001",
			{1=>text}]}}}}
	end	
end
