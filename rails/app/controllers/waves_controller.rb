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
		#render :text => @remote[params[:id]].inspect
		#return
		
		unless @wave.participants.include? @address
			delta = Delta.new @wave, @address
			delta << AddUserOp.new(@address)
    	@remote.add_delta @wave, delta
    	
			delta = Delta.new @wave, @address
			delta << MutateOp.new('b+main', @wave.playback.create_fedone_line('b+main', @address, "Hey there, I'm #{@address} "))
    	@remote.add_delta @wave, delta
    end
    
  end
  
  def ajax
		@wave = @remote[params[:id]]
		unless @wave
			render :text => @remote[params].inspect, :status => 404
			return
		end
		
		render :text => 'OK'
		
		#
		#if params[:message] && params[:message].size > 0
		#	delta = Delta.new @wave, @address
		#	#components = @wave.playback.create_fedone_line(@address, params[:message])
		#	total = 0
		#	start = 0
		#	old = nil
		#	@wave.contents.each do |content|
		#		if content.is_a? String
		#			if old == :next
		#				old = content
		#				start = total
		#			end
		#			total += content.size
		#		elsif content.is_a? Element
		#			total += 1
		#			if content.attributes['by'] == @address
		#				old = :next
		#			end
		#		else
		#			total += 1
		#		end
		#	end
		#	
		#	components = [{:retain_item_count => start},
		#	 {:delete_chars => old},
		#	 {:characters => params[:message]},
		#	 {:retain_item_count => total - start}]
		#	 
		#	delta << MutateOp.new('main', components)
    #	@remote.add_delta(@wave, delta)
    #end
		
		#version = @wave.newest_version
		#i = 0
		
		#while @remote[params[:id]].newest_version == version
			#sleep 1
			
			#i += 1
			#if i > 5
			#	render :text => @wave.to_xml.gsub('<line', '<br')
			#	return
			#end
			
		#end
		#	@wave = @remote[params[:id]]
  	#render :text => @wave.to_xml.gsub(/<line by="([^"]+)">\n<\/line>/, '<br/>&lt;\1&gt; ')
  end

  def update
		@wave = @remote[params[:id]]
		
		if @wave.participants.include? @address
			delta = Delta.new @wave, @address
			delta << MutateOp.new(params[:doc], @wave.playback.create_fedone_line(params[:doc], @address, params[:message]))
    	@remote.add_delta(@wave, delta)
    	flash[:notice] = "Your message has been added."
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
			delta = Delta.new @wave, @address
			delta << RemoveUserOp.new(params[:who])
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
			delta << AddUserOp.new(params[:who])
    	@remote.add_delta(@wave, delta)
    	flash[:notice] = "#{params[:who]} has been added to the wave."
    end
    
    redirect_to wave_path(@wave.name)
  end
end
