class WavesController < ApplicationController
	before_filter :require_user, :connect_remote

  def index
		@waves = @remote.all_waves
  end

  def show
		if params[:id] == 'new'
			@wave = Wave.new(@remote.provider)
			@remote << @wave
    	redirect_to wave_path(@wave.name)
			return
		end
		
		@wave = @remote[params[:id]]
		
		unless @wave.participants.include? @address
			delta = Delta.new @wave, @address
			delta.operations << AddUserOp.new(@address)
    	@remote.add_delta @wave, delta
    	
			delta = Delta.new @wave, @address
			delta.operations << MutateOp.new('main', @wave.playback.create_fedone_line(@address, "Hey there, I'm #{@address} "))
    	@remote.add_delta @wave, delta
    end
    
  end

  def update
		@wave = @remote[params[:id]]
		
		if @wave.participants.include? @address
			delta = Delta.new @wave, @address
			delta.operations << MutateOp.new('main', @wave.playback.create_fedone_line(@address, params[:message]))
    	@remote.add_delta(@wave, delta)
    	flash[:notice] = "Your message has been added."
    else
    	flash[:error] = 'You aren\'t in that wave.'
    end
    
    redirect_to wave_path(@wave.name) + '#contents'
  end

  def remove
		@wave = @remote[params[:id]]
		
		if !@wave.participants.include? @address
    	flash[:error] = 'fail.'
		elsif !( params[:who] && @wave.participants.include?(params[:who]) )
    	flash[:error] = "#{params[:who]} isn't in this wave."
    else
			delta = Delta.new @wave, @address
			delta.operations << RemoveUserOp.new(params[:who])
    	@remote.add_delta(@wave, delta)
    	flash[:notice] = "#{params[:who]} has been removed from the wave."
    end
    
    redirect_to wave_path(@wave.name)
  end

  def add
		@wave = @remote[params[:id]]
		
		if !@wave.participants.include? @address
    	flash[:error] = 'fail.'
		elsif !params[:who] || @wave.participants.include?(params[:who])
    	flash[:error] = "#{params[:who]} is already in this wave."
    else
			delta = Delta.new @wave, @address
			delta.operations << AddUserOp.new(params[:who])
    	@remote.add_delta(@wave, delta)
    	flash[:notice] = "#{params[:who]} has been added to the wave."
    end
    
    redirect_to wave_path(@wave.name)
  end
end
