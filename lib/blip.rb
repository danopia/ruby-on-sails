
module Sails

# Represents a certain version of a Blip at a certain point in time. Playback
# creates instances of this class for you. Mainly is a list of contents.
class Blip < Array
	attr_accessor :name, :authors, :last_changed
	
	def initialize name
		@name = name
		@authors = []
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
			
		arr.insert(0, {:retain_item_count=>item_count}) if item_count > 0
		arr
	end
	
	# Size of the blip's contents, strings are the number of bytes and everything
	# else counts as 1 byte
	def item_count
		inject(0) do |total, item|
			if item.is_a? String
				next total + item.size
			else
				next total + 1
			end
		end
	end
	
	# Dumps the current version of this Blip instance to XML. Note that said
	# XML probably won't be value XML in practice.
	def to_xml
		element_stack = []
		map do |item|
			if item.is_a? String
				item
				
			elsif item == :end
				"</#{element_stack.pop}>"
				
			elsif item.is_a? Element
				element_stack << item.type
				
				attribs = ''
				item.attributes.each_pair do |key, value|
					attribs << " #{key}=\"#{value}\""
				end
				
				"<#{item.type}#{attribs}>"
				
			else
				raise SailsError, "unknown document content type: #{item.class}"
			end
		end.join("\n")
	end
	
	# Apply a mutation. Does NO version checking!
	#
	# TODO: Handle mid-string stuff. Might add a whole class for mutations.
	def apply_mutate(author, operations)
		@authors << author unless @authors.include? author
	
		item = 0 # in the 'contents' array
		index = 0 # in a string
		operations.compact.each do |component|
			if component[:retain_item_count]
				advance = component[:retain_item_count]
				until advance == 0
					if !self[item].is_a?(String)
						advance -= 1
						item += 1
						index = 0
					elsif (self[item].size - index) <= advance
						advance -= (self[item].size - index)
						item += 1
						index = 0
					else # advance within current string
						index += advance
						advance = 0
					end
				end
				puts "Advanced #{component[:retain_item_count]} items"
			
			elsif component[:element_start]
				element = Element.new(component[:element_start][:type])
				(component[:element_start][:attributes] || []).each do |attribute|
					element.attributes[attribute[:key]] = attribute[:value]
				end
				
				self.insert(item, element)
				item += 1
				index = 0
			
			elsif component[:element_end]
				self.insert(item, :end)
				item += 1
				index = 0
			
			elsif component[:characters]
				self.insert(item, component[:characters])
				item += 1
				index = 0
			
			elsif component[:delete_chars]
				self.delete_at(item)
				index = 0
			end
		end
	end

end # class

# Represents an element starting tag.
class Element
	attr_accessor :type, :attributes
	def initialize(type=nil)
		@type = type
		@attributes = {}
	end
end

end # module
