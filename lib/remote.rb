require 'drb'

# Not inside the module, might move it later if the rails autoloader would
# still work.

# A class that's focused for use with DRb. There are a few methods that just
# call deeper methods, since DRb only sends method calls to the server if
# called on the main DRbObject. If it weren't for these methods, a DRb client
# wouldn't be able to do much.
class SailsRemote
	attr_accessor :drb, :provider
	
	# Serve a remote up
	def self.serve(provider, host=':9000')
		remote = SailsRemote.new(provider)
		remote.drb = DRb.start_service("druby://#{host}", remote)
		remote
	end
	
	# Connect to a remote
	def self.connect(host=':9000')
		DRb.start_service
		DRbObject.new nil, "druby://#{host}"
	end
	
	# Create a remote for the provider
	def initialize(provider)
		@provider = provider
		@drb = nil
	end
	
	# DRb's URI
	def uri
		@drb.uri if @drb
	end
	
	# Shuts down the DRb server
	def stop_service
		@drb.stop_service if @drb
		@drb = nil
	end
	
	# Returns a list of waves from all servers
	def all_waves
		waves = []
		@provider.servers.each_value do |server|
			waves += server.waves.values
		end
		waves.uniq
	end
	
	# Look up and return a wave
	def [](name)
		@provider[name]
	end
	# Add a wave
	def <<(wave)
		@provider << wave
	end
	
	# Add a delta to a wave (faster to give the wave's name). Also propagates the
	# delta.
	def add_delta(wave, delta)
		if wave.is_a? Sails::Wave
			wave << delta# unless wave.deltas.include?(delta)
			wave = wave.name
		end
		self[wave] << delta
		#delta.propagate
	end
	
	# Generate a random alphanumeric string
	def random_string(length=12)
		@letters ||= ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
		([''] * length).map { @letters[rand * @letters.size] }.join('')
	end
end

