require 'digest/md5'

class User < ActiveRecord::Base
	acts_as_authentic
	
	has_many :memberships
	has_many :groups, :through => :memberships
	has_many :contacts, :source => :user1
	has_many :deltas
	
	def self.gravatar address, size=80
		"http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(address.downcase)}?s=#{size}&d=identicon"
	end
	
	def gravatar size=80
		User.gravatar self.email, size
	end
	
	def public_name
		display_name || login
	end
	
	def address
		"#{login}@#{Sails::Remote.provider.domain}"
	end
	
	
	def to_html size=25
		img = ''
		img = "<img src=\"#{gravatar size}\" /> " unless size.nil?
		
		"#{img}<a href=\"/users/#{login}\">#{public_name}</a>"
	end
end
