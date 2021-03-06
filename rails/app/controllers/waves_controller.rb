class WavesController < ApplicationController
	before_filter :require_user, :connect_remote

  def index
		@waves = @remote.all_waves
  end

  def show
		if params[:id] == 'new'
			@wave = @remote.new_local_wave
			
			Sails::DeltaBuilder.build @wave, @address do
				add_self
				create_conv
			end
			
    	redirect_to wave_path(@wave.name)
			return
		end
		
		@wave = @remote[params[:id]]
		unless @wave
			render :text => 'No such wave.', :status => 404
			return
		end
		
		unless @wave.has_user? @address
			Sails::DeltaBuilder.build @wave, @address do
				add_self
			end
    end

  end
  
  def render_html blips
  	blips.map do |blip|
  		if blip.is_a? String
				"<p><strong>#{blip}</strong></p>\n<p><em>by #{@wave.blip(blip).authors.join(', ')}</em></p>\n#{@wave.blip(blip).to_xml}\n<hr/>"
			else
				"<blockquote>\n#{render_html blip}\n</blockquote>"
			end
		end.join("\n")
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
		
		if params[:message].empty?
			render :text => 'Please enter a message.'
			return
		end
		
		if @wave.has_user? @address
		
			Sails::DeltaBuilder.build @wave, @address do |builder|
				blip = builder.new_blip
				if params[:message].include? '--'
					parts = params[:message].split '--', 2
					builder.first_line_header blip, parts.first, parts.last
				else
					builder.first_line blip, params[:message]
				end
				
				if params[:parent] && params[:parent].any? && @wave.blip(params[:parent])
					builder.add_blip_under blip, params[:parent]
				else
					builder.add_blip_at_end blip
				end
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
		
		if !@wave.has_user? @address
    	flash[:error] = 'fail.'
		elsif !( params[:who] && @wave.has_user?(params[:who]) )
    	flash[:error] = "#{params[:who]} isn't in this wave."
    else
			Sails::DeltaBuilder.build @wave, @address do |builder|
				builder.remove_user params[:who]
			end
    	flash[:notice] = "#{params[:who]} has been removed from the wave."
    end
    
    redirect_to wave_path(@wave.name)
  end

  def add
		@wave = @remote[params[:id]]
		
		if !@wave.has_user? @address
    	flash[:error] = 'fail.'
		elsif !params[:who] || @wave.has_user?(params[:who])
    	flash[:error] = "#{params[:who]} is already in this wave."
    else
			Sails::DeltaBuilder.build @wave, @address do |builder|
				builder.add_user params[:who]
			end
    	flash[:notice] = "#{params[:who]} has been added to the wave."
    end
    
    redirect_to wave_path(@wave.name)
  end
end
