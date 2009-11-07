
module Sails

# Represents a Wave, either local or remote.
class Wave < Playback
	attr_accessor :provider, :host, :name, :deltas
	
	# Create a new wave. +name+ defaults to a random value and +host+ defaults
	# to the local provider's name.
	def initialize(provider, name=nil, host=nil)
		@provider = provider
		@name = name || provider.local.random_wave_name
		@host = host || provider.domain
		@deltas = {}
		
		super self
		
		self << FakeDelta.new(self)
	end
	
	# Returns a sorted list of all real deltas that this server has.
	def real_deltas
		@deltas.values.select{|delta| delta.is_a? Delta}.sort{|a, b| a.version <=> b.version}
	end
	
	# Builds a wave path in the form of host/w+wave
	def path
		"wave://#{@host}/w+#{@name}"
	end
	
	# Builds a wavelet path to 'conv+root' (for Fedone) in the form of
	# host/wave/conv+root
	def conv_root_path
		"#{path}/conv+root"
	end
	
	alias blip []
	# Returns a certain delta, by version number.
	def [](version)
		@deltas[version]
	end
	
	# Adds a delta to the wave.
	def <<(delta)
		@deltas[delta.version] = delta
		apply delta if complete?
	end
	
	# Returns the latest version number. Faster than newest.version
	def newest_version
		@deltas.keys.sort.last
	end
	
	# Returns the latest Delta (according to version)
	def newest
		@deltas[@deltas.keys.sort.last]
	end
	
	# Is the wave local?
	def local?
		@host == @provider.domain
	end
	
	# Determines if the wave has a complete history
	#
	# Pass true as the argument to request more history if incomplete; pass a
	# Hash and it'll set key packet-id to the current Wave.
	def complete?(request_more=false)
		fakes = @deltas.values.select do |delta|
			delta.is_a?(FakeDelta) && delta.version != 0
		end
		
		return true if fakes.empty?
			
		if request_more
			puts "Requesting more deltas for #{self.path}"
			
			server = @provider.servers[@host]
			unless server
				server = Server.new(@provider, @host, @host)
				@provider << server
			end
			
			id = @provider.random_packet_id
			server << ['iq', 'get', "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items node=\"wavelet\"><delta-history xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" start-version=\"0\" start-version-hash=\"#{encode64(self[0].hash)}\" end-version=\"#{self.newest_version}\" end-version-hash=\"#{encode64(self.newest.hash)}\" wavelet-name=\"#{self.conv_root_path}\"/></items></pubsub>", id]
			request_more[id] = self if request_more.is_a? Hash
		end
		
		false
	end
end # class

end # module
