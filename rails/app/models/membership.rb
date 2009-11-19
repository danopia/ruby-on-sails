class Membership < ActiveRecord::Base
	belongs_to :user
	belongs_to :group
	
	def local?
		user2_address.nil?
	end
end
