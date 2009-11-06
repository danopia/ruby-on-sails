require 'openssl'
require 'base64'

require 'digest/sha1'
require 'digest/sha2'

# Monkey-patch in some convenience methods.
class OpenSSL::X509::Name
	# Shortcut to look up a value.
	def [](key)
		to_hash[key]
	end

	# Convert the Name object in a Hash.
	def to_hash
		to_a.inject({}) do |hash, pair|
			hash[pair.first] = pair[1]
			hash
		end
	end
end

module Sails

	# Used for general Sails-related errors.
	class Error < RuntimeError; end
	
	# Triggered by the provider code only.
	class ProviderError < Error; end

	# Base64-encode the data with no newlines in the output.
	def encode64 data
		Base64.encode64(data).gsub("\n", '')
	end
	# Base64-decode the data.
	def decode64 data
		Base64.decode64(data)
	end

	# SHA1-digest the data. Returns a byte string.
	def sha1 data
		Digest::SHA1.digest data
	end
	# SHA256-digest the data. Returns a byte string.
	def sha2 data
		Digest::SHA2.digest data
	end

end
