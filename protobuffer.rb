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
	
			if (1..6).to_a.map{|num|(2+num*8)}.include?(raw.string[0]) || raw.string[0] == 8 || tree == [0, 2, 2, 1]
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






class ProtoBuffer
	def self.parse2(structure, data)
		data = StringIO.new(data)
		
		#puts "Parsing #{data.string.inspect}"
		
		hash = {}
		parse_args2 hash, data, structure until data.eof?
		
		#puts "Done."
		#pp hash
		
		hash
	end
	
	def self.parse_args2(parent_args, data, structure)
		key = data.getc
		key = (key / 8)
		
		value = nil
		
		substructure = structure[key]
		type = substructure
		type = type.first if type.is_a? Array
		
		unless type
			puts "UNEXPECTED KEY: #{key}"
			pp structure
			return
		end
		
		if type == :varint
			value = read_varint(data)
		
		elsif type == :boolean
			value = read_varint(data) == 1
		
		elsif type == :string
			value = read_string(data)
		
		elsif type.is_a? Hash
			value = {}
			raw = StringIO.new(read_string(data))
			parse_args2 value, raw, type until raw.eof?
		
		else
			puts "Unknown type: #{type}"
			return
		end
		
		if substructure.is_a? Array
			parent_args[key] ||= []
			parent_args[key] << value
		else
			puts "Overwritting a key!" if parent_args[key]
			parent_args[key] = value
		end
	end
end

key_value_pair = {
	1 => :string, # key
	2 => :string # value
}

key_value_update = {
	1 => :string, # key
	2 => :string, # old value, absent field means that the attribute was
		# absent/the annotationwas null.
	3 => :string, # new value, absent field means that the attribute should be
		# removed/the annotation should be set to null.
}


annotation_boundary = {
	1 => :boolean, # empty
	2 => [:string], # end, MUST NOT have the same string twice
	3 => [key_value_update]} # MUST NOT have two updates with the same key. MUST
		# NOT contain any of the strings listed in the 'end' field.

element_start = {
	1 => :string, # type
	2 => [key_value_pair] # attributes; MUST NOT have two pairs with the same key
}

replace_attributes = {
	1 => :boolean, # empty
	2 => [key_value_pair], # old attributes; MUST NOT have two pairs with the same key
	3 => [key_value_pair] # new attributes; MUST NOT have two pairs with the same key
}

update_attributes = {
	1 => :boolean, # empty
	2 => [key_value_update] # attribute update; MUST NOT have two updates with the same key
}

mutate_structure = {
	1 => :string, # document id (main)
	2 => {
		1 => [{
			1 => annotation_boundary,
			2 => :string, # characters
			3 => element_start,
			4 => :boolean, # element end
			5 => :varint, # retain item count
			6 => :string, # delete characters
			7 => element_start, # delete element start
			8 => :boolean, # delete element end
			9 => replace_attributes,
			10 => update_attributes}]}}


op_structure = {
	1 => :string, # Add participant
	2 => :string, # Remove participant
	3 => mutate_structure}

hashed_version = {1 => :varint, 2 => :string} # version, hash

delta_structure = {
	1 => hashed_version,
	2 => :string, # author
	3 => [op_structure]}

applied_structure = {
	1 => {
		1 => delta_structure,
		2 => {
			1 => :string, # signature
			2 => :string, # signer id
			3 => :varint}}, # signature alg (1 => SHA1-RSA)
	2 => hashed_version,
	3 => :varint, # operations applied
	4 => :varint} # timestamp, UNIX epoche * 1000 + milliseconds

require 'pp'
require 'base64'
def encode64(data)
	Base64.encode64(data).gsub("\n", '')
end
def decode64(data)
	Base64.decode64(data)
end

#pp ProtoBuffer.parse2(applied_structure, decode64('CpoCCm4KGAgIEhQx3X/ZwLVoYmCSHtYeyrpV+hdFphITZGFub3BpYUBkYW5vcGlhLm5ldBo9GjsKBG1haW4SMwojGiEKBGxpbmUSGQoCYnkSE2Rhbm9waWFAZGFub3BpYS5uZXQKAiABCggSBkhlbGxvLhKnAQqAAU4UJk+x0QLJmRW4CnJmKTjT2Hl/FJuCl6BCbjVUSObZLPNj3rC2vvcCfiSlT3dhkCYEq9AOYHdJKdiwsix7joHql0NUfb53maNtiIPJxciHvBGndRlBpeBYtDHr2+3/VRXEBNF/stFc0w24LGOt+EBGfdrW/BAqbQUpOu4auDHEEiByaAt3Th3lnLa43WcJcmBiOabN2b5GGbpBhRe+/NkEKhgBEhgICBIUMd1/2cC1aGJgkh7WHsq6VfoXRaYYASDogNjwyCQ='))
pp ProtoBuffer.parse2(delta_structure, "\n\030\b\b\022\0241\335\177\331\300\265hb`\222\036\326\036\312\272U\372\027E\246\022\023danopia@danopia.net\032=\032;\n\004main\0223\n#\032!\n\004line\022\031\n\002by\022\023danopia@danopia.net\n\002 \001\n\b\022\006Hello.")
