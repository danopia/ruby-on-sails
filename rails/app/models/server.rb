class Server < ActiveRecord::Base
	has_many :waves, :class_name => 'Wave'
	has_many :deltas
end
