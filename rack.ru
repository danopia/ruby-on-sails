require 'pp'

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
  	response[2].close # close rails, let it work for more stuff
  	
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
				
				body = "<html><head></head><body><div id=\"data\">#{escape @wave.to_xml}</div>(at version <span id=\"version\">#{version}</span>)</body></html>"
				
				env['async.callback'].call [200, {
					'Cache-Control' => 'no-cache',
					'Content-Type' => 'text/html; charset=utf-8',
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

	def each
		version = @wave.newest_version
		
		yield "<html><head></head><body><div id=\"data\">#{escape @wave.to_xml}</div>(at version <span id=\"version\">#{version}</span>)</body></html>"
		
		#data = data.size.to_s(16) + "\r\n" + data + "\r\n"
		#env['async.callback'].call [200, headers, wrap(data)]
		
		#sleep 5
		#i = 0
		#while i < 5
		#	i += 0.1
		#	sleep 0.1
			
		#	next unless @remote[$1].newest_version > version
		#	wave = @remote[$1]
		#	version = wave.newest_version
		#	data = "<script type=\"text/javascript\">
#	document.getElementById('data').innerHTML = \"#{escape_js wave.to_xml}\";
#	document.getElementById('version').innerHTML = \"#{version}\";
#</script>"
			
		#	data = data.size.to_s(16) + "\r\n" + data + "\r\n"
		#	env['async.callback'].call [200, headers, wrap(data)]
		#end
		
		#yield "<script type=\"text/javascript\">window.location.reload();</script>"
		yield "<script type=\"text/javascript\">alert('hi');</script>"
		
		#data = data.size.to_s(16) + "\r\n" + data + "\r\n0\r\n\r\n"
		
		#[200, headers, data]
		
		
		#term = "\r\n"
		#@body.each do |chunk|
		#	size = bytesize(chunk)
		#	next if size == 0
		#	yield [size.to_s(16), term, chunk, term].join
		#end
		#yield ["0", term, "", term].join
	end
  
  def escape text
  	text.gsub('<', '&lt;').gsub('>', '&gt;').gsub(/&lt;line by="([^"]+)"&gt;\n&lt;\/line&gt;/, '<br />&lt;\1&gt; ')
  end
  def escape_js text
  	escape(text).gsub('\\', '\\\\').gsub('"', '\\"').gsub("\n", ' ')
  end
end

use Rack::CommonLogger

rails_app = Rack::Adapter::Rails.new(:root => './wave.danopia.net')

app = Rack::URLMap.new('/ajax'  => SailsAdapter.new(rails_app),
                       '/' => rails_app)

run app
