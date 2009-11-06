
module Sails::Operations

# Represents the addition of a participant to a wave.
#
# === Usage ===
# 	delta << AddUserOp.new('me@danopia.net')
#
# 	operation = AddUserOp.new('echoey@danopia.net')
# 	operation.to_s #=> 'Added echoey@danopia.net to the wave'
# 	operation.to_hash #=> {0 => ['echoey@danopia.net']}
#
# 	operation = AddUserOp.new(['echoey@acmewave.com', 'meep@acmewave.com'])
# 	operation.to_s #=> 'Added echoey@acmewave.com, meep@acmewave.com to the wave'
# 	operation.to_hash #=> {0 => ['echoey@danopia.net', 'meep@acmewave.com'']}
class AddUser
	attr_accessor :who
	
	# Create a new AddUser operation, with the specified users being added.
	def initialize(who=[])
		who = [who] unless who.is_a? Array
		@who = who
	end
	
	# Create a hash, for use in ProtoBuffer encoding methods.
	def to_hash
		{:added => @who}
	end
	
	# Human-readable string; i.e. "Added me@danopia.net to the wave"
	def to_s
		"Added #{@who.join(', ')} to the wave"
	end
end

# Represents the removal of a participant from a wave.
#
# === Usage ===
# 	delta << RemoveUserOp.new('me@danopia.net')
#
# 	operation = RemoveUserOp.new('echoey@danopia.net')
# 	operation.to_s #=> 'Removed echoey@danopia.net from the wave'
# 	operation.to_hash #=> {1 => ['echoey@danopia.net']}
#
# 	operation = RemoveUserOp.new(['echoey@acmewave.com', 'meep@acmewave.com'])
# 	operation.to_s #=> 'Removed echoey@acmewave.com, meep@acmewave.com from the wave'
# 	operation.to_hash #=> {1 => ['echoey@danopia.net', 'meep@acmewave.com'']}
class RemoveUser
	attr_accessor :who
	
	# Create a new RemoveUser operation, with the specified users being added.
	def initialize(who=[])
		who = [who] unless who.is_a? Array
		@who = who
	end
	
	# Create a hash, for use in ProtoBuffer encoding methods.
	def to_hash
		{:removed => @who}
	end
	
	# Human-readable string; i.e. "Removed me@danopia.net from the wave"
	def to_s
		"Removed #{@who.join(', ')} from the wave"
	end
end

# Represents the mutation of the contents of a wavelet. TODO: Fix and document!
class Mutate
	attr_accessor :document_id, :components
	
	def initialize(document_id=nil, components=[])
		components = [components] unless components.is_a? Array
		
		@document_id = document_id
		@components = components
	end
	
	def self.parse(data)
		doc = data[:document_id]
		components = data[:mutation][:components]
		p Mutate.new(doc, components)
		Mutate.new(doc, components)
	end
	
	def to_hash
		{:mutate => {
			:mutation => {
				:components => @components},
			:document_id => @document_id}}
	end
	
	def to_s
		components.last.values.first
	end
end

end # module

