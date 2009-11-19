class Delta < ActiveRecord::Base
	belongs_to :server
	belongs_to :user
	belongs_to :wave
	
	def local?
		!(user_id.nil?)
	end
end
