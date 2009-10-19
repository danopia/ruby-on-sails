require 'socket'
require 'stringio'

class WaveSocket
	attr_reader :username, :domain, :address, :waves, :sock, :next_sequence
	
	def initialize(address, host, port=9876)
		@address = address
		@username, @domain = address.split('@')
		@waves = []
		@next_sequence = 0
		@sock = TCPSocket.open(host, port)
	end
	
	def send(packet)
		@next_sequence += 1
		packet.sequence = @next_sequence
		
		@sock.print packet.to_s
		puts packet.to_s.inspect
	end
	
	def recv
		Packet.parse @sock
	end
	
	def has_wave?(id)
		@waves.select{|wave|wave.id == id}.any?
	end
	def find_wave(id)
		@waves.select{|wave|wave.id == id}.first
	end
	
	def request_wave_list
		request_wave '!indexwave'
	end
	def request_wave(wave)
		packet = Packet.new 'waveserver.ProtocolOpenRequest'
		packet[0] = @address
		
		if wave.is_a? Wave
			packet[1] = "#{wave.domain}!#{wave.id}"
			packet[2] = "#{wave.domain}!conv+root"
		else
			packet[1] = wave
		end
		
		send packet
	end
	
	def new_wave(id=nil)
		Wave.new id, @domain
	end
end

class Packet
	attr_accessor :type, :args
	attr_writer :sequence
	
	def initialize(type='')
		@type = type
		@args = {}
	end
	
	def [](key)
		@args[key]
	end
	def []=(key, value)
		@args[key] = value
	end
	
	def self.parse(sock)
		# "\001\036waveserver.ProtocolOpenRequest \n\020test@danopia.net\022\n!indexwave\032\000"
		
		packet = Packet.new
		data = StringIO.new(sock.read(sock.read(4).unpack('I').first))
		puts data.string.inspect
		packet.sequence = read_varint(data)
		packet.type = read_string(data)
		
		payload = StringIO.new(read_string(data))
		
		puts "Starting a parse"
		until payload.eof?
			parse_args packet.args, payload, [packet.type]
		end
		puts "Done."
		p packet.args
		
		packet
	end
	
	def self.parse_args(parent_args, data, tree)
		key = (data.getc-10)/8
		return if key == -2
		
		puts ('  '*tree.size) + "Parsing \##{key}. Tree: #{tree.join(' -> ')}"
		args = {}
		raw = StringIO.new(read_string(data))
		
		if raw.string[0] == 8
			raw.getc
			value = read_varint(raw)
			puts ('  '*tree.size) + "Int: #{value}"
			parent_args[key] ||= []
			parent_args[key] << value
			return
		end
		
		unless (1..10).to_a.map{|num|(2+num*8)}.include?(raw.string[0])
			puts ('  '*tree.size) + "String: #{raw.string}"
			parent_args[key] ||= []
			parent_args[key] << raw.string
			return
		end
		
		tree << key
		until raw.eof?
			parse_args args, raw, tree
		end
		tree.pop
		
		parent_args[key] ||= []
		parent_args[key] << args
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
				value |= byte << index
				#io.ungetc byte
				return value
			end
		end
	end
	def self.read_string(io)
		io.read read_varint(io)
	end

	def write_varint(value)
		bytes = ''
		while value > 0x7F
			bytes << ((value & 0x7F) | 0x80).chr
			value >>= 7
		end
		bytes << value.chr
	end
	def write_string(io, string)
		io << write_varint(string.size) << string
	end
	
	def sequence
		return @sequence if @sequence
		
		@@sequence ||= 0
		@@sequence += 1
		@sequence = @@sequence
	end
	
	def raw
		packet = write_varint sequence
		write_string packet, @type
		write_string packet, write_args(@args)
		packet
	end
	
	def write_args(args)
		output = ''
		args.each_pair do |type, value|
			value = [value] unless value.is_a? Array
			value.each do |arg|
				output << (type*8+10).chr
				if arg.is_a? Hash
					write_string output, write_args(arg)
				elsif arg.is_a? Fixnum
					output << write_varint(arg)
				else
					write_string output, arg
				end
			end
		end
		output
	end
	
	def to_s
		[raw.size].pack('I') + raw
	end
end

class Wave
	attr_accessor :id, :domain, :participants, :messages, :revisions, :summary
	
	def initialize(id=nil, domain=nil)
		@id = id
		@domain = domain
		@participants = []
		@messages = []
		@revisions = []
	end
end

class Revision
	attr_accessor :wave, :id, :author
	attr_accessor :added_participants, :removed_participants, :deltas
	
	def initialize(wave=nil, id=0, author=nil)
		@wave = wave
		@id = id
		@author = author
		@added_participants = []
		@removed_participants = []
		@deltas = []
	end
end
