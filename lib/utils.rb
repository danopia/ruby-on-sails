require 'openssl'
require 'base64'

require 'digest/sha1'
require 'digest/sha2'

# Monkey-patch in some convenience methods. The module is separately entered
# for RDoc.
module OpenSSL #:nodoc: all
	class X509::Name
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
end

module Sails

	module Utils
	
		# Generate a random alphanumeric string
		def self.random_string length=12
			@letters ||= ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
			([''] * length).map { @letters[rand * @letters.size] }.join('')
		end

		# Base64-encode the data with no newlines in the output.
		def self.encode64 data
			Base64.encode64(data).gsub("\n", '')
		end
		# Base64-decode the data.
		def self.decode64 data
			Base64.decode64(data)
		end

		# SHA1-digest the data. Returns a byte string.
		def self.sha1 data
			Digest::SHA1.digest data
		end
		# SHA256-digest the data. Returns a byte string.
		def self.sha2 data
			Digest::SHA2.digest data
		end
		
		# Parse a wave://server/w+wave/wavelet address into 3 parts.
		def self.parse_wavelet_address address
			raise StandardError, 'invalid format' unless address =~ /^wave:\/\/(.+)\/w\+(.+)\/(.+)$/
			[$1, $2, $3]
		end
		
		# Formats some Base64 to make it valid enough for X509 to read it.
		def self.format_x509 cert
			return cert if cert.include? 'BEGIN CERTIFICATE'
			cert = Base64.encode64(Base64.decode64(cert)) # add line breaks
			"-----BEGIN CERTIFICATE-----\n#{cert}-----END CERTIFICATE-----\n"
		end
	
	end

	# Used for general Sails-related errors.
	class Error < RuntimeError; end
	
	# Triggered by the provider code only.
	class ProviderError < Error; end

end
