class Wave < ActiveRecord::Base
	belongs_to :server
	has_many :deltas
	
	# Builds a wave path in the form of host/w+wave
	def path
		"wave://#{server.domain}/w+#{name}"
	end
	
	# Builds a wavelet path to 'conv+root' (for Fedone) in the form of
	# host/wave/conv+root
	def conv_root_path
		"#{path}/conv+root"
	end
	
	# Is the wave local?
	def local?
		server_id.nil?
	end
end
