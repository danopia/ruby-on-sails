
module Sails

# Implements some base stuff for Delta and FakeDelta to inherit
class BaseDelta
	attr_accessor :wave, :version, :hash, :operations
	attr_reader :hash
	
	# Create a fake delta. It defaults to being the infamous "version 0" for a
	# wave. If you need to be anything else, you can pass the version/hash to
	# the initializer or use version= and hash=.
	def initialize(wave, version=0, hash=nil)
		@wave = wave
		@version = version
		@hash = hash
		@operations = []
	end
	
	def applied_to
		@wave[@version - @operations.size]
	end
end

end # module
