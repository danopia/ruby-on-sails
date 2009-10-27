class WavesController < ApplicationController
	before_filter :require_user, :connect_remote

  def index
		@address = "#{current_user.login}@danopia.net"
		@waves = @remote.all_waves
  end

  def show
		@address = "#{current_user.login}@danopia.net"
		
		if params[:id] == 'new'
			@wave = Wave.new(@remote.provider, 'asdf')
			@remote << @wave
    	redirect_to wave_path(@wave.name)
			return
		end
		
		@wave = @remote[params[:id]]
		
		unless @wave.participants.include? @address
			delta = Delta.new @wave, @address
			delta.operations << AddUserOp.new(@address)
			delta.operations << MutateOp.new('main', create_fedone_line(@address, "Hey there, this is #{@address}, and I'm using Ruby on Sails!"))
    	@remote.add_delta @wave, delta
    end
    
  end

  def update
		@address = "#{current_user.login}@danopia.net"
		
		@wave = @remote[params[:id]]
		
		if @wave.participants.include? @address
			delta = Delta.new @wave, @address
			delta.operations << MutateOp.new('main', create_fedone_line(@address, params[:message]))
    	render :text => @remote.add_delta(@wave, delta).inspect
    	
    	#redirect_to wave_path(@wave.name) + '#r' + delta.version.to_s
    else
    	render :text => 'fail.'
    end
  end

  def remove
		@address = "#{current_user.login}@danopia.net"
		@wave = @remote[params[:id]]
		
		if !@wave.participants.include? @address
    	flash[:error] = 'fail.'
		elsif !( params[:who] && @wave.participants.include?(params[:who]) )
    	flash[:error] = "#{params[:who]} isn't in this wave."
    else
			delta = Delta.new @wave, @address
			delta.operations << RemoveUserOp.new(params[:who])
    	@remote.add_delta(@wave, delta)
    end
    
    redirect_to wave_path(@wave.name) + '#r' + delta.version.to_s
  end

	protected
	
	def create_fedone_line(author, text)
		[{:element_start=>
			{:type=>"line",
			 :attributes=>
				[{:value=>author, :key=>"by"}]}},
		 {:element_end=>true},
		 {:characters=>text}]
	end
	
	def connect_remote
		return if @remote
		@remote = SailsRemote.connect
		DRb.start_service
	end
end
