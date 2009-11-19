class Server < ActiveRecord::Base
	has_many :waves
	has_many :deltas
end
