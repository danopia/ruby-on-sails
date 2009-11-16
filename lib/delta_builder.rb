
module Sails

# Cute class, mainly designed for prettyness. Used to build up Delta objects.
#
# TODO: Document! Document! Document!
class DeltaBuilder
	attr_reader :wave, :delta, :author
	
	def initialize delta
		@wave = delta.wave
		@delta = delta
		@author = delta.author
	end
	
	def author= author
		@delta.author = author
		@author = @delta.author
	end
	
	def create_conv
		mutate 'conversation', [
			{:element_start => {:type => 'conversation'}},
			{:element_end => true}
		]
	end
	
	def add_blip_at_end blip
		add_blip_at_index blip, @wave.conv.size - 1
	end
	
	def new_blip_at_end initial_line=nil
		blip = new_blip initial_line
		add_blip_at_end blip
		blip
	end
	
	def add_blip_after blip, target
		add_blip_x_after_end blip, target, 0
	end
	
	def new_blip_after target, initial_line=nil
		blip = new_blip initial_line
		add_blip_after blip, target
		blip
	end
	
	def add_blip_under blip, target
		add_blip_x_after_end blip, target, -1
	end
	
	def new_blip_under target, initial_line=nil
		blip = new_blip initial_line
		add_blip_under blip, target
		blip
	end
	
	def new_blip initial_line=nil, blip=nil
		blip = "b+#{Sails::Utils.random_string 6}" unless blip
		mutate blip # create with no operation
		first_line blip, initial_line if initial_line
		blip
	end
	
	def first_line blip, message
		mutate blip, [
			{:element_start=>{:type=>"body"}},
			{:element_start=>{:type=>"line"}},
			{:element_end => true},
			{:characters => message},
			{:element_end => true}
		]
	end
	
	def first_line_header blip, header, message
		mutate blip, [
			{:element_start=>{:type=>"body"}},
			
			{:element_start=>{:type=>"line", :attributes => [{:key => 't', :value => 'h1'}]}},
			{:element_end => true},
			{:characters => header},
			
			{:element_start=>{:type=>"line"}},
			{:element_end => true},
			{:characters => message},
			
			{:element_end => true}
		]
	end
	
	def append_line blip, message
		blip = @wave.blip(blip) unless blip.is_a? Sails::Blip
		
		mutate blip, [
			{:retain_item_count => blip.contents.size - 1},
			{:element_start=>{:type=>"line"}},
			{:element_end => true},
			{:characters => message},
			{:retain_item_count => 1}
		]
	end
	
	def add operation
		@delta << operation
	end
	
	def add_user participant
		add Operations::AddUser.new(@wave.provider.find_or_create_user(participant))
	end
	def remove_user participant
		add Operations::RemoveUser.new(@wave.provider.find_or_create_user(participant))
	end
	def mutate blip, components=[]
		blip = blip.name if blip.is_a? Sails::Blip
		add Operations::Mutate.new(blip, components)
	end
	
	def add_self
		add_user @author
	end
	
	protected
	
	def add_blip_at_index blip, index=1
		blip = blip.name if blip.is_a? Blip
		
		mutate 'conversation', [
			{:retain_item_count => index},
			{:element_start=>{:type => 'blip', :attributes => [{:key=>'id', :value=>blip}]}},
			{:element_end => true},
			{:retain_item_count => @wave.conv.size - index}
		]
	end
	
	def add_blip_x_after_end blip, target, x=0
		target = target.name if target.is_a? Blip
		
		target = @wave.conv.select do |item|
			item.is_a?(Element) && item['id'] == target
		end.first
		return nil unless target
		
		index = @wave.conv.index(target) + 1
		depth = 1
		while depth > 0
			if @wave.conv[index].is_a? Element
				depth += 1
			elsif @wave.conv[index] == :end
				depth -= 1
			end
			index += 1
		end
		
		add_blip_at_index blip, index + x
	end
	
	def self.build wave, author, &block
		delta = Delta.new wave, author
		builder = DeltaBuilder.new delta
		block.arity < 1 ? builder.instance_eval(&block) : block.call(builder)
		wave << delta
		delta
	end
end # class

end # module
