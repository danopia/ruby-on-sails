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
end
