require 'digest/md5'

# Methods added to this helper will be available to all templates in the application.

module ApplicationHelper
	def icon_tag(icon, *args)
		image_tag "/images/icons/#{icon}.png", *args
	end
	
	def gravatar(email, size=80)
		email ||= 'fail'
		"http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email.downcase)}?s=#{size}&d=identicon"
	end
	
	def empty?(field)
		return true if field == nil
		return field == ''
	end
end
