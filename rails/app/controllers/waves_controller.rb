class WavesController < ApplicationController
	before_filter :require_user, :connect_remote

  def index
		@waves = @remote.all_waves
  end

  def show
		if params[:id] == 'new'
			@wave = @remote.new_local_wave
			
			Sails::Delta.build @remote, @wave, @address do
				add_self
				create_conv
			end
			
    	redirect_to wave_path(@wave.name)
			return
		end
		
		@wave = @remote[params[:id]]
		
		unless @wave.participants.include? @address
			Sails::Delta.build @remote, @wave, @address do
				add_self
			end
    end
    
  end
  
  def ajax
		@wave = @remote[params[:id]]
		unless @wave
			render :text => @remote[params].inspect, :status => 404
			return
		end
		
		render :text => 'OK'
  end

  def update
		@wave = @remote[params[:id]]
		
		if @wave.participants.include? @address
		
			Sails::Delta.build @remote, @wave, @address do |builder|
				builder.new_blip_at_end params[:message]
			end
			
    	#flash[:notice] = "Your message has been added."
    else
    	flash[:error] = 'You aren\'t in that wave.'
    end
    
    #redirect_to wave_path(@wave.name) + '#contents'
    render :j => 'alert("Updated.");'
  end

  def remove
		@wave = @remote[params[:id]]
		
		if !@wave.participants.include? @address
    	flash[:error] = 'fail.'
		elsif !( params[:who] && @wave.participants.include?(params[:who]) )
    	flash[:error] = "#{params[:who]} isn't in this wave."
    else
			Sails::Delta.build @remote, @wave, @address do |builder|
				builder.remove_user params[:who]
			end
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
			Sails::Delta.build @remote, @wave, @address do |builder|
				builder.add_user params[:who]
			end
    	flash[:notice] = "#{params[:who]} has been added to the wave."
    end
    
    redirect_to wave_path(@wave.name)
  end
end
