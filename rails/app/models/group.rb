class Group < ActiveRecord::Base
	#belongs_to :owner, :source => :user, :class_name => :user
	belongs_to :user
	has_many :memberships
	has_many :users, :through => :memberships
	
	def addresses
		memberships.map {|membership| membership.address }
	end
end
