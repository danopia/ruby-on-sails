
module Sails

# Represents a certain version of a Wave. Starts at version 0 and can be played
# back, version by version, to HEAD. At any step, you can grab participants,
# XML representation, etc.
class Playback
	attr_accessor :wave, :version, :participants, :blips, :conv
	
	# Creates a new Playback instance for a wave. Without a version param, it
	# defaults to starting at version 0. This is useful for playing through a
	# wave step-by-step. You can also pass :newest, a Delta, or a version number,
	# as it's passed right to Playback#apply.
	def initialize(wave, version=0)
		@wave = wave
		@version = 0
		@participants = []
		@blips = []
		@blips2 = []
		@conv = []
		
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
			if op.is_a? Operations::AddUser
				@participants += op.who
				pp op.who
			end
			@participants -= op.who if op.is_a? Operations::RemoveUser
			if op.is_a? Operations::Mutate
				puts "Mutation to #{op.document_id}"
				if op.document_id == 'conversation'
					self.apply_conv_mutate(op.components)
				else
					if op.components.any?
						self.blip(op.document_id).apply_mutate(delta.author, op.components) 
					else
						puts "New blip #{op.document_id}"
						@blips2 << Blip.new(op.document_id)
					end
				end
			end
		end
		
		@version = version
	end
	
	# Look up a blip or create it
	def [] blip_id
		blips = @blips2.flatten.select {|blip| blip.name == blip_id}
		return blips.first if blips.any?
		
		Blip.new blip_id
	end
	alias blip []
	
	def parent blip
		blip find(blip.name, @blips)
	end
	
	def find needle, haystack
		haystack.each do |item|
			if item.is_a? Array
				result = find(needle, item)
				if result == true
					return haystack[haystack.index(item) - 1]
				elsif result
					return result
				end
			elsif item == needle
				return true
			end
		end
		nil
	end
	
	protected
	
	# Apply a mutation. Does NO version checking!
	def apply_conv_mutate(operations)
		item = 0 # in the 'conv' array
		operations.compact.each do |component|
			if component[:retain_item_count]
				item += component[:retain_item_count]
			
			elsif component[:element_start]
				element = Element.new(component[:element_start][:type])
				(component[:element_start][:attributes] || []).each do |attribute|
					element[attribute[:key]] = attribute[:value]
				end
				
				@conv.insert(item, element)
				item += 1
			
			elsif component[:element_end]
				@conv.insert(item, :end)
				item += 1
			end
		end
		
		read_conv
	end
	
	def read_conv
		stack = [[]]
		
		@conv.each do |item|
			if item.is_a? Element
				next if item.type == 'conversation'
				stack.last << item['id']
				stack.push []
			elsif item == :end && stack.size >= 2
				arr = stack.pop
				stack.last << arr if arr.any?
			end
		end
		
		@blips = stack
	end
	
end # class

end # module
