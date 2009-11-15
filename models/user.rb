require 'digest/md5'

class User < ActiveRecord::Base
	acts_as_authentic
	
	def gravatar size=80
		"http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(self.email.downcase)}?s=#{size}&d=identicon"
	end
	
	def public_name
		self.display_name || self.login
	end
end
