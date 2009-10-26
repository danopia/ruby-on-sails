require 'stringio'

class ProtoBuffer
	def self.structures
		@structures ||= {}
	end
	
	def self.parse(structure, data)
		data = StringIO.new(data)
		hash = {}
		structure = structures[structure] if structure.is_a? Symbol
		
		parse_field hash, data, structure until data.eof?
		
		hash
	end
	
	def self.parse_field(parent_args, data, structure)
		key = data.getc / 8
		label = nil
		value = nil
		
		type = substructure = structure[key]
		type = type.first if type.is_a? Array
		
		unless type
			puts "UNEXPECTED KEY: #{key}"
			puts "Expected one of #{structure.keys.join(', ')}"
			return
		end
		
		if type.is_a? Param
			label = type.label
			type = type.type
		end
		
		if type == :varint
			value = read_varint(data)
		
		elsif type == :boolean
			value = read_varint(data) == 1
		
		elsif type == :string
			value = read_string(data)
		
		elsif type.is_a?(Hash) || type.is_a?(Symbol)
			if type.is_a? Symbol
				label ||= type
				type = structures[type]
			end
			
			value = {}
			raw = StringIO.new(read_string(data))
			parse_field value, raw, type until raw.eof?
		
		else
			puts "Unknown type: #{type}"
			return
		end
		
		label ||= key
		if substructure.is_a? Array
			parent_args[label] ||= []
			parent_args[label] << value
		else
			puts "Overwritting a key!" if parent_args[key]
			parent_args[label] = value
		end
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
	
	class Param
		attr_accessor :type, :label
		
		def initialize(type, label)
			@type = type
			@label = label
		end
	end
	
	def self.structure(key, structure)
		structures[key] = structure
	end
	
	def self.method_missing(type, label=nil)
		label ||= type if type.is_a? Symbol
		Param.new(type, label)
	end
	
	
	structure :hashed_version, {1 => varint(:version), 2 => string(:hash)}

	structure :delta, {
		1 => hashed_version(:applied_to),
		2 => string(:author),
		3 => [operation(:operations)]
	}
	
	
	structure :key_value_pair, {1 => string(:key), 2 => string(:value)}

	structure :key_value_update, {
		1 => string(:key),
		2 => string(:old_value), # absent field means that the attribute was
			# absent/the annotation was null.
		3 => string(:new_value), # absent field means that the attribute should be
			# removed/the annotation should be set to null.
	}


	structure :annotation_boundary, {
		1 => boolean(:empty),
		2 => [string(:end)], # MUST NOT have the same string twice
		3 => [:key_value_update]} # MUST NOT have two updates with the same key. MUST
			# NOT contain any of the strings listed in the 'end' field.

	structure :element_start, {
		1 => string(:type),
		2 => [key_value_pair(:attributes)] # MUST NOT have two pairs with the same key
	}

	structure :replace_attributes, {
		1 => boolean(:empty),
		2 => [key_value_pair(:old_attributes)], # MUST NOT have two pairs with the same key
		3 => [key_value_pair(:new_attributes)] #  MUST NOT have two pairs with the same key
	}

	structure :update_attributes, {
		1 => boolean(:empty),
		2 => [key_value_update(:updates)] # MUST NOT have two updates with the same key
	}
	
	structure :document_op, {
		1 => [mutate_component(:components)]}
			
	structure :mutate_component, {
		1 => :annotation_boundary,
		2 => string(:characters),
		3 => :element_start,
		4 => boolean(:element_end),
		5 => varint(:retain_item_count),
		6 => string(:delete_chars),
		7 => element_start(:delete_element_start),
		8 => boolean(:delete_element_end),
		9 => :replace_attributes,
		10 => :update_attributes}
			
	structure :mutate, {
		1 => string(:document_id), # always 'main' as far as I can tell
		2 => document_op(:mutation)}


	structure :operation, {
		1 => string(:added),
		2 => string(:removed),
		3 => :mutate,
		4 => boolean(:noop)}
	
	structure :delta_signature, {
		1 => string(:signature),
		2 => string(:signer_id),
		3 => varint(:signer_id_alg)} # 1 = SHA1-RSA
	
	structure :signed_delta, {
		1 => :delta,
		2 => delta_signature(:signature)} # 1 = SHA1-RSA

	structure :applied_delta, {
		1 => signed_delta,
		2 => hashed_version(:applied_to),
		3 => varint(:operations_applied),
		4 => varint(:timestamp)} # UNIX epoche * 1000 + milliseconds

end


require 'pp'
require 'base64'
def encode64(data)
	Base64.encode64(data).gsub("\n", '')
end
def decode64(data)
	Base64.decode64(data)
end

pp ProtoBuffer.parse(:applied_delta, decode64('CpoCCm4KGAgIEhQx3X/ZwLVoYmCSHtYeyrpV+hdFphITZGFub3BpYUBkYW5vcGlhLm5ldBo9GjsKBG1haW4SMwojGiEKBGxpbmUSGQoCYnkSE2Rhbm9waWFAZGFub3BpYS5uZXQKAiABCggSBkhlbGxvLhKnAQqAAU4UJk+x0QLJmRW4CnJmKTjT2Hl/FJuCl6BCbjVUSObZLPNj3rC2vvcCfiSlT3dhkCYEq9AOYHdJKdiwsix7joHql0NUfb53maNtiIPJxciHvBGndRlBpeBYtDHr2+3/VRXEBNF/stFc0w24LGOt+EBGfdrW/BAqbQUpOu4auDHEEiByaAt3Th3lnLa43WcJcmBiOabN2b5GGbpBhRe+/NkEKhgBEhgICBIUMd1/2cC1aGJgkh7WHsq6VfoXRaYYASDogNjwyCQ='))
puts
pp ProtoBuffer.parse(:delta, "\n\030\b\b\022\0241\335\177\331\300\265hb`\222\036\326\036\312\272U\372\027E\246\022\023danopia@danopia.net\032=\032;\n\004main\0223\n#\032!\n\004line\022\031\n\002by\022\023danopia@danopia.net\n\002 \001\n\b\022\006Hello.")
