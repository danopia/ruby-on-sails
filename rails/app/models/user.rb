require 'digest/md5'

class User < ActiveRecord::Base
	acts_as_authentic
	
	def self.gravatar address, size=80
		"http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(address.downcase)}?s=#{size}&d=identicon"
	end
	
	def gravatar size=80
		User.gravatar self.email, size
	end
	
	def public_name
		self.display_name || self.login
	end
end
