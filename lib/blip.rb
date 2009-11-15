
module Sails

# Represents a certain version of a Blip at a certain point in time. Playback
# creates instances of this class for you. Mainly is a list of contents.
class Blip
	attr_accessor :name, :authors, :last_changed, :contents, :special, :annotations
	
	def initialize name
		@name = name
		@authors = []
		@contents = ''
		@special = []
		@annotations = []
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
		#puts "---------"
		
		element_stack = []
		special_index = 0
		
		annotations = {}
		users = []
		@annotations.each do |annotation|
			annotations[annotation.start] ||= []
			annotations[annotation.start] << annotation
			
			if annotation =~ /^user\/d\/(.+)$/
				users << $1
			end
		end
		#puts "indexes: #{annotations.keys.join ', '}"
		
		string = @contents.clone
		@contents.size.times do |index|
			index = @contents.size - 1 - index
			#puts "at index #{index}"
			(annotations[index] || []).each do |annotation|
				puts "adding annotation #{annotation.key} = #{annotation.value}"
				
				if annotation.key =~ /^user\/e\/(.+)$/
					annotation.value =~ /^(.+)@(.+)$/
					text = "<span class=\"blinkybit\">#{$1 || annotation.value}</span>"
					users.delete $1
				else
					text = ''#"&lt;annotation: #{annotation.key} = #{annotation.value} /&gt;"
				end
				
				string.insert index, text
			end
		end
		
		#p users
		string += users.map do |user|
			"<span class=\"blinkybit\">#{user}</span>"
		end.join ''
		
		#puts "---------"
		
		open = false
		string.gsub! "\001" do
			item = @special[special_index]
			special_index += 1
			
			if item == :end
				next '' if (element_stack.last.nil? || element_stack.last == 'body') && element_stack.pop.nil?
				"</#{element_stack.pop}>"
				
			elsif item.is_a? Element
				
				if item.type == 'line'
					tag = 'p'
					tag = item['t'] if item['t']
					
					element_stack << nil
					opening = "<#{tag}>"
					if open
						opening = "</#{open}>#{opening}"
					end
					open = tag
					
					opening
				
				else
					element_stack << item.type
					
					next '' if item.type == 'body'
					
					attribs = ''
					item.each_pair do |key, value|
						attribs << " #{key}=\"#{value}\""
					end
					
					"<#{item.type}#{attribs}>"
				end
				
			else
				raise Sails::Error, "unknown document content type: #{item.class}"
			end
			
		end
		
		string += "</#{open}>" if open
		string
	end
	
	# Apply a mutation. Does NO version checking!
	#
	# TODO: Handle mid-string stuff. Might add a whole class for mutations.
	def apply_mutate(author, operations)
		pp operations
		p @contents
		
		@authors << author unless @authors.include? author
		
		current_annotations = {}
	
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
				move_annotations index
				index += 1
				special_index += 1
			
			elsif component[:update_attributes]
				element = @special[special_index]
				(value[:updates] || []).each do |attribute|
					element[attribute[:key]] = attribute[:new_value]
				end
				
				index += 1
				special_index += 1
			
			elsif component[:element_end]
				@contents.insert index, "\001"
				@special.insert special_index, :end
				move_annotations index
				index += 1
				special_index += 1
			
			elsif component[:characters]
				@contents.insert index, value
				move_annotations index, value.size
				index += value.size
			
			elsif component[:delete_chars]
				if @contents[index, value.size] != value
					raise Sails::Error, "chars to delete didn't match existing chars"
				end
				
				move_annotations index, -value.size
				@contents.slice! index, value.size
			
			elsif component[:annotation_boundary]
			
				(value[:key_value_update] || []).each do |update|
					if update[:old_value]
						if current_annotations[update[:key]]
							#if !update[:new_value] || update[:new_value].empty?
							#	@annotations.delete current_annotations[update[:key]]
							#	current_annotations.delete update[:key]
							#end
						else
							current_annotations[update[:key]] = @annotations.select do |annotation|
								annotation.start <= index && annotation.end >= index && annotation.key == update[:key]
							end.first
							
							if current_annotations[update[:key]]
								current_annotations[update[:key]].end = index
							else
								current_annotations.delete update[:key]
							end
						end
					end
					
					if update[:key] =~ /^user\//
						@annotations.delete_if do |annotation|
							annotation.key == update[:key]
						end
					end
					
					update[:new_value] ||= update[:old_value]
					#if update[:new_value] && update[:new_value].any?
						annotation = Annotation.new update[:key], update[:new_value], index
						current_annotations[update[:key]] = annotation
						@annotations << annotation
					#end
				end
			
				(value[:end] || []).each do |key|
					if current_annotations[key]
						current_annotations[key].end = index
						current_annotations.delete key
					end
				end
			
			end
		end
		
		p @contents
		
		if index != @contents.size
			raise Sails::Error, "didn't end up at the end of the contents array. #{@contents.size - index} bytes too short."
		end
		
		if current_annotations.any?
			pp current_annotations
			raise Sails::Error, "annotation update hash was left with #{current_annotations.size} unclosed annotations. supposed to be 0."
		end
	end
	
	def move_annotations starting, distance=1
		@annotations.each do |annotation|
			annotation.start += distance if annotation.start >= starting
			annotation.end += distance if annotation.end >= starting
			annotation.end = annotation.start + 1 if annotation.end <= annotation.start
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
