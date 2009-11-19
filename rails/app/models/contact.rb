class Contact < ActiveRecord::Base
	belongs_to :user1, :class_name => :user
	belongs_to :user2, :class_name => :user
	
	def local?
		address.nil?
	end
end
