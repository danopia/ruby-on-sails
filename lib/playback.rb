
module Sails

# Represents a certain version of a Wave. Starts at version 0 and can be played
# back, version by version, to HEAD. At any step, you can grab participants,
# XML representation, etc.
class Playback
	attr_accessor :wave, :version, :participants, :documents
	
	# Creates a new Playback instance for a wave. Without a version param, it
	# defaults to starting at version 0. This is useful for playing through a
	# wave step-by-step. You can also pass :newest, a Delta, or a version number,
	# as it's passed right to Playback#apply.
	def initialize(wave, version=0)
		@wave = wave
		@version = 0
		@participants = []
		@documents = {}
		
		self.apply version if version != 0
	end
	
	# Returns true if this Playback instance is at the latest version of the
	# wave.
	def at_newest?
		@version == @wave.newest_version
	end
	
	# Applies the specified delta, including any before it if necesary. Shortcuts
	# are :next and :newest. You can also use a version number.
	def apply(version)
		if !version.is_a?(Delta) && !version.is_a?(FakeDelta)
			if version == :next
				version = @version + 1
				version += 1 until @wave[version]
			end
			
			version = @wave.newest_version if version == :newest
			#pp @wave.deltas
			delta = @wave[version]
		else
			delta = version
			version = delta.version
		end
		
		if version <= @version
			puts "Delta #{version} is already applied; at #{@version}."
			return false
		elsif !@wave.complete?
			puts "The wave isn't complete; I can't apply a delta yet."
			return false
		end
	
		if (version - delta.operations.size) > @version
			puts "Need to apply #{version - @version - 1} deltas first."
			apply :next until @version == version - delta.operations.size
		end
		
		puts "Applying delta #{version} to #{@wave.path}"
		
		delta.operations.each do |op|
			@participants += op.who if op.is_a? Operations::AddUser
			@participants -= op.who if op.is_a? Operations::RemoveUser
			apply_mutate(op) if op.is_a? Operations::Mutate
		end
		
		@version = version
	end
	
	# Dumps the current version of this Playback instance to XML. Note that said
	# XML probably won't be value XML in practice.
	def to_xml(document_id='main')
		element_stack = []
		@documents[document_id].map do |item|
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
	
	# Size of the wave's contents, strings are the number of bytes and everything
	# else counts as one
	def item_count(doc)
		doc.inject(0) do |total, item|
			if item.is_a? String
				next total + item.size
			else
				next total + 1
			end
		end
	end
	
	# Hackity hack
	def create_fedone_line(doc, author, text)
		doc = @documents[doc] ||= [] unless doc.is_a? Array
		if self.item_count(doc) > 0
			[{:retain_item_count=>self.item_count(doc)},
			 {:element_start=>
				{:type=>"line",
				 :attributes=>
					[{:value=>author, :key=>"by"}]}},
			 {:element_end=>true},
			 {:characters=>text}]
		else
			[{:element_start=>
				{:type=>"line",
				 :attributes=>
					[{:value=>author, :key=>"by"}]}},
			 {:element_end=>true},
			 {:characters=>text}]
		end
	end
	
	protected
	
	# Apply a mutation. Does NO version checking!
	#
	# TODO: Handle mid-string stuff. Might add a whole class for mutations.
	def apply_mutate(operation)
		doc = @documents[operation.document_id] ||= []
		
		item = 0 # in the 'contents' array
		index = 0 # in a string
		operation.components.compact.each do |component|
			if component[:retain_item_count]
				advance = component[:retain_item_count]
				until advance == 0
					if !doc[item].is_a?(String)
						advance -= 1
						item += 1
						index = 0
					elsif (doc[item].size - index) <= advance
						advance -= (doc[item].size - index)
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
				
				doc.insert(item, element)
				item += 1
				index = 0
			
			elsif component[:element_end]
				doc.insert(item, :end)
				item += 1
				index = 0
			
			elsif component[:characters]
				doc.insert(item, component[:characters])
				item += 1
				index = 0
			
			elsif component[:delete_chars]
				doc.delete_at(item)
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
