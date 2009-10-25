class WavesController < ApplicationController
	before_filter :require_user

  def index
		@address = "#{current_user.login}@danopia.net"
		
		remote = SailsRemote.connect
		@waves = remote.waves
    #DRb.start_service
  end

  def show
		@address = "#{current_user.login}@danopia.net"
		
		remote = SailsRemote.connect
		
		if params[:id] == 'new'
			@wave = Wave.new('danopia.net', random_name)
			remote << @wave
    	redirect_to wave_path(@wave.name)
			return
		end
		
		@wave = remote[params[:id]]
		
		unless @wave.participants.include? @address
			delta = Delta.new @wave, @address
			delta.operations << AddUserOp.new(@address)
			delta.operations << MutateOp.new('main', create_fedone_line(@address, "Hey there, this is #{@address}, and I'm using Ruby on Sails!"))
    	remote.add_delta @wave, delta
    end
    
  end

  def update
		@address = "#{current_user.login}@danopia.net"
		
		remote = SailsRemote.connect
		@wave = remote[params[:id]]
		
		if @wave.participants.include? @address
			delta = Delta.new @wave, @address
			delta.operations << MutateOp.new('main', create_fedone_line(@address, params[:message]))
    	remote.add_delta @wave, delta
    	
    	redirect_to wave_path(@wave.name) + '#r' + delta.version.to_s
    else
    	render :text => 'fail.'
    end
  end

	protected
	
	def create_fedone_line(author, text)
		#{2=>{2=>{0=>"main",1=> {0=>
		[#"(\004",
			{2=>{0=>"line", 1=>{0=>"by", 1=>author}}}," \001",
			{1=>text}]#}}}}
	end	
end
