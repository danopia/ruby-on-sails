require 'drb'

module Sails

# A class that's focused for use with DRb. There are a few methods that just
# call deeper methods, since DRb only sends method calls to the server if
# called on the main DRbObject. If it weren't for these methods, a DRb client
# wouldn't be able to do much.
class Remote
	attr_accessor :drb, :provider
	
	class << self
		attr_reader :provider, :remote # Current remote/provider
	end
	
	# Serve a remote up
	def self.serve provider, host=':9000'
		@remote = Sails::Remote.new provider
		@remote.drb = DRb.start_service "druby://#{host}", @remote
		
		@provider = provider
		@remote
	end
	
	# Connect to a remote
	def self.connect host=':9000'
		DRb.start_service
		@remote = DRbObject.new nil, "druby://#{host}"
		
		@provider = @remote.provider
		@remote
	end
	
	# Create a remote for the provider
	def initialize provider
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
	def [] name
		@provider[name]
	end
	
	# Add a delta or wave
	def << item
		if item.is_a? Wave
			@provider << item
		elsif item.is_a? Delta
			wave = self[item.wave.name]
			add_delta wave, item
		else
			raise Sails::Error, "unexpected object passed"
		end
	end
	
	# Add a delta to a wave (faster to give the wave's name). Also propagates the
	# delta.
	def add_delta(wave, delta)
		if wave.is_a? Wave
			wave << delta# unless wave.deltas.include?(delta)
			wave = wave.name
		end
		self[wave] << delta
	end
	
	def new_local_wave
		wave = Wave.new @provider
		self << wave
		wave
	end
end # class

end # module
