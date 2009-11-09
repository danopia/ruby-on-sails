
module Sails

# Represents a Wave, either local or remote.
class Wave < Playback
	attr_accessor :provider, :server, :name, :deltas
	
	# Create a new wave. +name+ defaults to a random value and +host+ defaults
	# to the local provider's name.
	def initialize(provider, name=nil, server=nil)
		@provider = provider
		@name = name || provider.local.random_wave_name
		@deltas = {}
		
		if server.is_a? String
			server = provider.find_or_create_server server
		end
		@server = server || provider.local
		
		super self
		
		self << FakeDelta.new(self)
	end
	
	# Builds a wave path in the form of host/w+wave
	def path
		"wave://#{@server.domain}/w+#{@name}"
	end
	
	# Builds a wavelet path to 'conv+root' (for Fedone) in the form of
	# host/wave/conv+root
	def conv_root_path
		"#{path}/conv+root"
	end
	
	alias blip []
	# Returns a certain delta, by version number.
	def [](version)
		if version.is_a? String
			blip version
		else
			return nil if version > newest_version
			version += 1 until @deltas[version]
			@deltas[version]
		end
	end
	
	# Adds a delta or blip to the wave.
	def <<(item)
		if item.is_a? BaseDelta
			@deltas[item.version] = item
			item.propagate if item.is_a?(Delta)
			
		elsif item.is_a? Blip
			if blip(item.name)
				raise SailsError, 'This blip already exists.'
			else
				raise SailsError, 'Not implemented yet.'
			end
		else
			raise ArgumentError, 'expected a Blip, Delta, or FakeDelta'
		end
	end
	
	# Returns the latest version number. Faster than newest.version
	def newest_version
		@deltas.keys.sort.last
	end
	
	# Returns the latest Delta (according to version)
	def newest
		@deltas[newest_version]
	end
	
	# Is the wave local?
	def local?
		@server == @provider.local
	end
	
	def request_history first=nil, last=nil
		puts "Requesting more deltas for #{self.path}"
		
		first ||= self[0]
		last ||= self.newest
		first = [first.version, first.hash] if first.is_a? BaseDelta
		last = [last.version, last.hash] if last.is_a? BaseDelta
		
		@server << ['iq', 'get', "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items node=\"wavelet\"><delta-history xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" start-version=\"#{first[0]}\" start-version-hash=\"#{encode64(first[1])}\" end-version=\"#{last[0]}\" end-version-hash=\"#{encode64(last[1])}\" wavelet-name=\"#{self.conv_root_path}\"/></items></pubsub>"]
	end
	
	def request_cert delta, signer_id=nil
		if delta.is_a? BaseDelta
			delta = [delta.prev_hash, delta.prev_version]
			signer_id ||= delta.signer_id
		end
		
		@server << ['iq', 'get', "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items node=\"signer\"><signer-request xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" signer-id=\"#{encode64 signer_id}\" history-hash=\"#{encode64 delta[0]}\" version=\"#{delta[1]}\" wavelet-name=\"#{conv_root_path}\"/></items></pubsub></iq>"]
	end
	
	def post delta
		return unless delta.local?
		
		@server << ['iq', 'set', "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish node=\"wavelet\"><item><submit-request xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"><delta wavelet-name=\"#{conv_root_path}\"><![CDATA[#{encode64(delta.to_s)}]]></delta></submit-request></item></publish></pubsub>"]
	end
	
	# Determines if the wave has a complete history
	#
	# Pass true as the argument to request more history if incomplete; pass a
	# Hash and it'll set key packet-id to the current Wave.
	def complete?(request_more=false)
		@deltas.each_value do |delta|
			if delta.is_a?(FakeDelta) && delta.version != 0
				request_history nil, delta
				return false
			end
		end
		
		true
	end
end # class

end # module
