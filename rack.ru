require 'pp'
require 'sails'

class SailsAdapter
	def initialize(rails_app)
		@rails = rails_app
	end
	
	def connect
		return if @remote
		@remote = SailsRemote.connect
		DRb.start_service
	end
	
  def call(env)
  	response = @rails.call env
  	return response unless (200..299).include? response[0]
  	response[2].close # release rails, let it work for other requests
  	
		connect # to the remote
		
		@wave = nil
		1/0 unless env['PATH_INFO'] =~ /^\/waves\/(.+)$/
		name = $1
		@wave = @remote[name]
		version = @wave.newest_version
  	
  	elapsed = 0
  	timer = EventMachine::PeriodicTimer.new(0.1) do
  		elapsed += 0.1
			if elapsed > 5 || @remote[name].newest_version > version
				timer.cancel
				
				@wave = @remote[name]
				version = @wave.newest_version
				
				body = @wave.blips.flatten.map do |blip|
					"<p><strong>#{doc_id}</strong></p>\n#{escape blip.to_xml}\n<hr/>"
				end.join("\n")
				
				env['async.callback'].call [200, {
					'Cache-Control' => 'no-cache',
					'Content-Type' => 'text/xml; charset=utf-8',
				}, body]
				
				env['rack.errors'].write %{%s - %s [%s] "%s %s%s %s" %d\n} % [
        env['HTTP_X_FORWARDED_FOR'] || env["REMOTE_ADDR"] || "-",
        env["REMOTE_USER"] || "-",
        Time.now.strftime("%d/%b/%Y %H:%M:%S"),
        env["REQUEST_METHOD"],
        env["PATH_INFO"],
        env["QUERY_STRING"].empty? ? "" : "?"+env["QUERY_STRING"],
        env["HTTP_VERSION"],
        200 ]
				
			end
		
		end

  	[-1, {}, []]
  end
  
	#	data = "<script type=\"text/javascript\">
#	document.getElementById('data').innerHTML = \"#{escape_js wave.to_xml}\";
#	document.getElementById('version').innerHTML = \"#{version}\";
#</script>"
	
	#yield "<script type=\"text/javascript\">window.location.reload();</script>"
  
  def escape text
  	text.gsub('<', '&lt;').gsub('>', '&gt;')
  end
  def escape_js text
  	escape(text).gsub('\\', '\\\\').gsub('"', '\\"').gsub("\n", ' ')
  end
end

use Rack::CommonLogger

rails_app = Rack::Adapter::Rails.new(:root => './rails')

mapping = {'/ajax'  => SailsAdapter.new(rails_app),
           '/' => rails_app}

if File.exists? File.join(File.dirname(__FILE__), 'doc')
	mapping['/doc'] = Rack::File.new('./doc')
end

app = Rack::URLMap.new(mapping)

run app
