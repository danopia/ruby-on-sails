require 'stringio'

class ProtoBuffer
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
	

	def self.encode(structure, hash)
		structure = reverse_structures[structure] if structure.is_a? Symbol
		output = ''
		
		hash.each_pair do |type, value|
			value = [value] unless value.is_a? Array
			key = type
			
			substructure = structure[type]
			substructure = substructure.first if substructure.is_a? Array
			
			if substructure.is_a? Param
				key = substructure.index
				substructure = substructure.type
			end
			
			if substructure.is_a?(Symbol) && !([:varint, :string, :boolean].include?(substructure))
				substructure = reverse_structures[substructure]
			end

			value.each do |arg|
				if substructure == :varint
					output << (key*8).chr
					output << write_varint(arg.to_i)
					
				elsif substructure == :boolean
					output << (key*8).chr
					output << write_varint(arg ? 1 : 0)
					
				elsif substructure == :string
					output << (key*8+2).chr
					write_string output, arg
					p "String: #{arg}"
					
				elsif substructure.is_a?(Hash) || type.is_a?(Symbol)
					if substructure.is_a? Symbol
						substructure = structures[substructure]
					end
					
					output << (key*8+2).chr
					write_string output, encode(substructure, arg)
					p "Sub structure..."
				
				else
					puts "Unknown type: #{type}"
					return
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
	
	############
	# DSL stuff
	
	class Param
		attr_accessor :type, :label, :index
		
		def initialize(type, label, index=nil)
			@type = type
			@label = label
			@index = index
		end
	end
	
	def self.structures
		@structures ||= {}
	end
	
	def self.reverse_structures
		@reverse_structures ||= {}
	end
	
	# Yay ugly
	def self.structure(key, structure)
		structure.each_pair do |index, type|
			type = type.first if type.is_a? Array
			type.index = index if type.is_a? Param
		end
		
		structures[key] = structure
		
		reverse = {}
		structure.each_pair do |key2, type|
			reverse[key2] = type # so that indexes still work
			
			type2 = type
			type2 = type.first if type.is_a? Array
			
			label = key2
			if type2.is_a? Param
				if type2.label
					label = type2.label
				elsif type.type.is_a? Symbol
					label = type2.type
				end
			elsif type2.is_a?(Symbol) && !([:varint, :string, :boolean].include?(type2))
				label = type2
			end
			
			reverse[label] = type
		end
		
		reverse_structures[key] = reverse
	end
	
	def self.method_missing(type, label=nil)
		label ||= type if type.is_a? Symbol
		Param.new(type, label)
	end
end
