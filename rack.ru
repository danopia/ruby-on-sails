require 'pp'
require 'sails'

puts "Connecting to the database"
#Sails::Database.connect

module Sails

class RackAdapter
	def initialize(rails_app)
		@rails = rails_app
	end
	
	def connect
		return if @remote
		@remote = Remote.connect
		DRb.start_service
	end
	
  def call(env)
  	response = @rails.call env
  	return response unless (200..299).include? response[0]
  	response[2].close # release rails, let it work for other requests
  	
		connect # to the remote
		
		@wave = nil
		1/0 unless env['PATH_INFO'] =~ /^\/waves\/(.+)\/([0-9]+)$/
		name = $1
		version = $2.to_i
		@wave = @remote[name]
  	
  	elapsed = 0
  	interval = 0.1
  	
  	timer = EventMachine::PeriodicTimer.new(interval) do
  		elapsed += interval
			if elapsed > 5 || @remote[name].newest_version > version
				timer.cancel
				
				body = []
				if @remote[name].newest_version > version
					@wave = @remote[name]
					#version = @wave.newest_version
					until version == @remote[name].newest_version
						delta = @wave[version + 1]
						version = delta.version
						
						delta.operations.each do |operation|
							if operation.is_a? Operations::Mutate
								unless operation.document_id == 'conversation'
									blip = @wave.blips[operation.document_id]
									parent = blip.parent_blip
									parent = if parent
										"'#{parent.name}'"
									else
										'undefined'
									end
									
									authors = blip.authors.map {|author| author.to_html }
									
									body << "update_blip('#{blip.name}', #{parent}, '#{authors.join(', ')}', \"#{escape_js blip.to_xml}\");"
								end # unless
							elsif operation.is_a? Operations::RemoveUser
								operation.who.each do |who|
									body << "remove_user('#{who}');"
								end # each
							else#if operation.is_a? Operations::AddUser
								operation.who.each do |who|
									html = who.to_s
									html = who.to_html if who.respond_to? :to_html
									body << "add_user('#{who}', '#{html}');"
								end # each
							end # if
						end # each
					end # until
				end # if
				
				body << "version = #{version};"
				
				env['async.callback'].call [200, {
					'Cache-Control' => 'no-cache',
					'Content-Type' => 'text/javascript; charset=utf-8',
				}, body.uniq.join("\n")]
				
				env['rack.errors'].write %{%s - %s [%s] "%s %s%s %s" %d\n} % [
        env['HTTP_X_FORWARDED_FOR'] || env["REMOTE_ADDR"] || "-",
        env["REMOTE_USER"] || "-",
        Time.now.strftime("%d/%b/%Y %H:%M:%S"),
        env["REQUEST_METHOD"],
        env["PATH_INFO"],
        env["QUERY_STRING"].empty? ? "" : "?"+env["QUERY_STRING"],
        env["HTTP_VERSION"],
        200 ]
				
			end # timer block
		
		end # on elapsed

  	[-1, {}, []]
  end # def call
  
#	data = "<script type=\"text/javascript\">
#	document.getElementById('data').innerHTML = \"#{escape_js wave.to_xml}\";
#	document.getElementById('version').innerHTML = \"#{version}\";
#</script>"
	
	#yield "<script type=\"text/javascript\">window.location.reload();</script>"
  
  def escape text
  	text.gsub('<', '&lt;').gsub('>', '&gt;')
  end
  def escape_js text
  	text.gsub('\\', '\\\\').gsub('"', '\\"')
  end
end # class
end # module

use Rack::CommonLogger

rails_app = Rack::Adapter::Rails.new(:root => './rails')

mapping = {'/ajax'  => Sails::RackAdapter.new(rails_app),
           '/' => rails_app}

if File.exists? File.join(File.dirname(__FILE__), 'doc')
	mapping['/doc'] = Rack::File.new('./doc')
end

app = Rack::URLMap.new(mapping)

run app
