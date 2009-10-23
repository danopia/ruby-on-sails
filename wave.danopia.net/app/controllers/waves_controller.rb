class WavesController < ApplicationController
	before_filter :require_user

  def index
		@address = "#{current_user.login}@danopia.net"
		
		remote = SailsRemote.connect ':9000'
		@waves = remote.wave_list
  end

  def show
		@address = "#{current_user.login}@danopia.net"
		
		remote = SailsRemote.connect ':9000'
		
		if params[:id] == 'new'
			@wave = Wave.new('danopia.net', random_name)
			remote << @wave
    	redirect_to wave_path(@wave.name)
			return
		end
		
		@wave = remote[params[:id]]
		
		unless @wave.participants.include? @address
			delta = @wave.new_delta @address
			delta.operations << AddUserOp.new(@address)
    	remote.add_delta @wave, delta
			
			#delta = @wave.new_delta @address
			#delta.operations << create_text_mutate(@address, "Hey there, this is #{@address}, and I'm using Ruby on Sails!")
    	#server.add_delta @wave.name, delta
    end
    
  end

  def update
		@address = "#{current_user.login}@danopia.net"
		
		remote = SailsRemote.connect ':9000'
		@wave = remote[params[:id]]
		
		if @wave.participants.include? @address
			delta = @wave.new_delta @address
			delta.operations << MutateOp.new('main', "<line by='#{@address}'/>" + params[:message])
    	remote.add_delta @wave, delta
    end
    
    redirect_to wave_path(@wave.name) + '#r' + delta.version.to_s
  end

	protected
	
	def create_text_mutate(author, text)
		{2=>{2=>{0=>"main",1=> {0=>["(\004",
			{2=>{0=>"line", 1=>{0=>"by", 1=>author}}}," \001",
			{1=>text}]}}}}
	end	
end
