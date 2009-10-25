require 'stringio'

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
			puts "#{'  '*(tree.size)}#{key} => int: #{value}"
		
		elsif type == 2 # Fixed-width (e.g. strings)
			value = {}
			raw = StringIO.new(read_string(data))
	
			if (1..8).to_a.map{|num|(2+num*8)}.include?(raw.string[0]) || raw.string[0] == 8 || tree == [0, 2, 2, 1]
				puts "#{'  '*tree.size}parsing \##{key}. Tree: #{tree.join(' -> ')} Data: #{raw.string.inspect}"
				parse_args value, raw, tree + [key] until raw.eof?
			else
				puts "#{'  '*tree.size}#{key} => string: #{raw.string.inspect}"
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
