class WavesController < ApplicationController
	before_filter :require_user, :connect_remote

  def index
		@waves = @remote.all_waves
  end

  def show
		if params[:id] == 'new'
			@wave = Sails::Wave.new(@remote.provider)
			@remote << @wave
			
			delta = Sails::Delta.new @wave, @address
			delta << Sails::Operations::Mutate.new(delta, 'conversation', [
				{:element_start=>{:type=>"conversation"}},
				{:element_end => true}
			])
			
    	@remote.add_delta(@wave, delta)
			
    	redirect_to wave_path(@wave.name)
			return
		end
		
		@wave = @remote[params[:id]]
		
		unless @wave.participants.include? @address
			delta = Sails::Delta.new @wave, @address
			delta << Sails::Operations::AddUser.new(delta, @address)
    	@remote.add_delta @wave, delta
    	
			#delta = Sails::Delta.new @wave, @address
			#delta << Sails::Operations::Mutate.new(delta, 'b+main', @wave.blip('b+main').create_fedone_line(@address, "Hey there, I'm #{@address} "))
    	#@remote.add_delta @wave, delta
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
			blip = 'b+' + @remote.random_string(6)
			
			delta = Sails::Delta.new @wave, @address
			delta << Sails::Operations::Mutate.new(delta, 'conversation', [
				{:retain_item_count => 1 + @wave.blips.size*2},
				{:element_start=>{:type=>"blip", :attributes => [{:value=>blip, :key=>"id"}]}},
				{:element_end => true},
				{:retain_item_count => 1}
			])
			delta << Sails::Operations::Mutate.new(delta, blip, [])
			delta << Sails::Operations::Mutate.new(delta, blip, [
				{:element_start=>{:type=>"body"}},
				{:element_start=>{:type=>"line"}},
				{:element_end => true},
				{:characters => params[:message]},
				{:element_end => true}
			])
			
			#delta << Sails::Operations::Mutate.new(delta, params[:doc], @wave.blip(params[:doc]).create_fedone_line(@address, params[:message]))
    	@remote.add_delta(@wave, delta)
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
			delta = Sails::Delta.new @wave, @address
			delta << Sails::Operations::RemoveUser.new(delta, params[:who])
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
			delta = Sails::Delta.new @wave, @address
			delta << Sails::Operations::AddUser.new(delta, params[:who])
    	@remote.add_delta(@wave, delta)
    	flash[:notice] = "#{params[:who]} has been added to the wave."
    end
    
    redirect_to wave_path(@wave.name)
  end
end
