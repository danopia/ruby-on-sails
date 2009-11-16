
module Sails

class Thread < Array
	attr_accessor :parent, :id, :inline, :peers
	
	def initialize parent=nil, id=nil
		@parent = parent
		id ||= Utils.random_string(4)
		@id = id
		@inline = false
		@peers = []
		
		super()
	end
	
	def flatten
		kids = []
		self.each do |blip|
			kids += blip.flatten
		end
		kids
	end
	
end # class

end # module
