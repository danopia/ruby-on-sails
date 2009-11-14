
module Sails

class Annotation
	attr_accessor :key, :value, :start, :end
	
	def initialize key=nil, value=nil, start=0
		@key = key
		@value = value
		@start = start
		@end = start
	end
	
	def key_parts
		@key.split '/'
	end
	
	def type
		key_parse.first
	end
	
	def style?
		type == 'style'
	end
	def user?
		type == 'user'
	end
	def link?
		type == 'link'
	end
	
end # class

end # module
