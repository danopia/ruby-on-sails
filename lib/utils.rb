require 'openssl'
require 'base64'

require 'digest/sha1'
require 'digest/sha2'

class OpenSSL::X509::Name
	def [](key)
		to_hash[key]
	end

	def to_hash
		to_a.inject({}) do |hash, pair|
			hash[pair.first] = pair[1]
			hash
		end
	end
end

module Sails

	class Error < RuntimeError; end
	class ProviderError < Error; end

	def encode64 data
		Base64.encode64(data).gsub("\n", '')
	end
	def decode64 data
		Base64.decode64(data)
	end

	def sha1 data
		Digest::SHA1.digest data
	end
	def sha2 data
		Digest::SHA2.digest data
	end

end
