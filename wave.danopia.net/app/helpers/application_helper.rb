# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
	def icon_tag(icon, *args)
		image_tag "/images/icons/#{icon}.png", *args
	end
end
