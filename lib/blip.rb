
module Sails

# Represents a certain version of a Blip at a certain point in time. Playback
# creates instances of this class for you. Mainly is a list of contents.
class Blip
	attr_accessor :name, :authors, :last_changed, :contents, :special
	
	def initialize name
		@name = name
		@authors = []
		@contents = ''
		@special = []
	end
	
	# Hackity hack
	def create_fedone_line(author, text)
		arr = [
			{:element_start=>
				{:type=>"line",
				 :attributes=>
					[{:value=>author, :key=>"by"}]}},
			{:element_end=>true},
			{:characters=>text}]
			
		arr.insert(0, {:retain_item_count=>item_count}) if @contents.size > 0
		arr
	end
	
	def digest
		@contents.gsub("\001", '')
	end
	
	# Dumps the current version of this Blip instance to XML. Note that said
	# XML probably won't be value XML in practice.
	def to_xml
		element_stack = []
		special_index = 0
		
		@contents.gsub "\001" do
			item = @special[special_index]
			special_index += 1
			
			if item == :end
				"</#{element_stack.pop}>"
				
			elsif item.is_a? Element
				element_stack << item.type
				
				attribs = ''
				item.each_pair do |key, value|
					attribs << " #{key}=\"#{value}\""
				end
				
				"<#{item.type}#{attribs}>"
				
			else
				raise Sails::Error, "unknown document content type: #{item.class}"
			end
			
		end
	end
	
	# Apply a mutation. Does NO version checking!
	#
	# TODO: Handle mid-string stuff. Might add a whole class for mutations.
	def apply_mutate(author, operations)
		@authors << author unless @authors.include? author
	
		index = 0 # in the 'contents' array
		special_index = 0 # in the 'special' array
		operations.compact.each do |component|
			value = component.values.first
			
			if component[:retain_item_count]
				string = @contents[index, value]
				special_index += string.count("\001")
				index += value
			
			elsif component[:element_start]
				element = Element.new value[:type]
				(value[:attributes] || []).each do |attribute|
					element[attribute[:key]] = attribute[:value]
				end
				
				@contents.insert index, "\001"
				@special.insert special_index, element
				index += 1
				special_index += 1
			
			elsif component[:element_end]
				@contents.insert index, "\001"
				@special.insert special_index, :end
				index += 1
				special_index += 1
			
			elsif component[:characters]
				@contents.insert index, value
				index += value.size
			
			elsif component[:delete_chars]
				if @contents[index, value.size] != value
					raise Sails::Error, "chars to delete didn't match existing chars"
				end
				
				@contents.slice! index, value.size
			end
		end
		
		if index != @contents.size
			raise Sails::Error, "didn't end up at the end of the contents array. #{@contents.size - index} bytes too short."
		end
	end

end # class

# Represents an element starting tag.
class Element < Hash
	attr_accessor :type
	def initialize(type=nil)
		@type = type
		super()
	end
end

end # module
