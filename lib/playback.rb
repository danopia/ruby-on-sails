
module Sails

# Represents a certain version of a Wave. Starts at version 0 and can be played
# back, version by version, to HEAD. At any step, you can grab participants,
# XML representation, etc.
class Playback
	attr_accessor :wave, :version, :participants, :thread, :conv, :blips
	
	# Creates a new Playback instance for a wave. Without a version param, it
	# defaults to starting at version 0. This is useful for playing through a
	# wave step-by-step. You can also pass :newest, a Delta, or a version number,
	# as it's passed right to Playback#apply.
	def initialize(wave, version=0)
		@wave = wave
		@version = 0
		@participants = []
		@conv = []
		@blips = {}
		
		self.apply version if version != 0
	end
	
	def thread
		@conv.first
	end
	
	# Returns true if this Playback instance is at the latest version of the
	# wave.
	def at_newest?
		@version == @wave.newest_version
	end
	
	def has_user? address
		@participants.select do |user|
			user.to_s == address.to_s.downcase
		end.any?
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
		end
		version = delta.version
		
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
				@participants += op.who.map do |user|
					@wave.provider.find_or_create_user user
				end
			end
			
			if op.is_a? Operations::RemoveUser
				@participants.delete_if do |user|
					op.who.include? user.to_s
				end
			end
			
			if op.is_a? Operations::Mutate
				puts "Mutation to #{op.document_id}"
				if op.document_id == 'conversation'
					apply_conv_mutate op.components
				else
					if op.components.any?
						@blips[op.document_id].apply_mutate delta.author, op.components
					else
						@blips[op.document_id] = Blip.new op.document_id
						puts "New blip #{op.document_id}"
					end
				end
			end
		end
		
		@version = version
	end
	
	# Look up a blip or create it
	def [](blip_id)
		blips = @thread.flatten.select {|blip| blip.name == blip_id}
		return blips.first if blips.any?
		
		Blip.new blip_id
	end
	alias blip []
	
	protected
	
	# Apply a mutation. Does NO version checking!
	def apply_conv_mutate(operations)
		index = 0
		stack = []
		
		operations.compact.each do |component|
			if component[:retain_item_count]
				component[:retain_item_count].times do
					if @conv[index] == :end
						stack.pop
					else
						stack << @conv[index]
					end
					index += 1
				end
			
			elsif component[:element_start]
				
				attributes = {}
				(component[:element_start][:attributes] || []).each do |attribute|
					attributes[attribute[:key]] = attribute[:value]
				end
				
				item = nil
				case component[:element_start][:type]
					when 'conversation': item = Thread.new; @thread = item
					when 'blip': item = @blips[attributes['id']]
					when 'thread': item = Thread.new(stack.last, attributes['id'])
				end
				
				raise "wth is #{component[:element_start][:type]}" unless item
				
				item.parent = stack.last || self
				stack.last << item if stack.last
				stack << item
				
				@conv.insert index, item
				index += 1
			
			elsif component[:element_end]
				@conv.insert index, :end
				stack.pop
				index += 1
			
			end
		end
	end
	
end # class

end # module
