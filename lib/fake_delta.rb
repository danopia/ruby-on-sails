
module Sails

# Represents an unknown delta. Used for the fake "version 0" and for gaps in
# history, so we can store hashes without storing any other details.
class FakeDelta < BaseDelta

	# Create a fake delta. It defaults to being the infamous "version 0" for a
	# wave. If you need to be anything else, you can pass the version/hash to
	# the initializer or use version= and hash=.
	def initialize wave, version=0, hash=nil
		super wave, version, hash || wave.conv_root_path
		@operations = [{:noop => true}]
	end
end

end # module
