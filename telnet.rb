#!/usr/bin/env ruby

require 'gserver'
require 'sails'

class SailsTelnetServer < GServer
	def initialize(port=23, host='localhost', maxConnections = 20, *args)
		super(port, host, maxConnections, *args)
		@remote = SailsRemote.connect
	end
	
	def serve(io)
		name = 'telnet'
		address = "#{name}@#{@remote.provider.domain}"
		redraw io
		
		while true
			line = io.gets.chomp
			params = line.split ' '
			next if params.empty?
			
			case params.first.downcase
				when '/quit'
					io.puts 'Bye!'
					return
				
				when '/user'
					name = params[1]
					address = "#{name}@#{@remote.provider.domain}"
					io.puts "Connecting as #{address}...."
					
					redraw io
			end
			
		end
	end
	
	def redraw(io)
		io.print `clear`
		if @remote.all_waves.any?
			io.puts "Waves:"
			i = 0
			@remote.all_waves.each do |wave|
				io.puts ' ---+---------------------------------------------------'
				io.puts "  #{i} |\tw+#{wave.name}@#{wave.host}"#\t<#{wave[0].author}> #{wave[0].operations.first}"
				p wave.blips
				wave.blips.flatten.each do |blip|
					io.puts "    |\t\t\t#{blip.name}: #{Hpricot(blip.to_xml).first_child.inner_text}"
				end
				i += 1
			end
			io.puts ' ---+---------------------------------------------------'
		else
			io.puts 'No waves exist.'
		end
	end
	
	def error(detail)
		log(detail.inspect)
    log(detail.backtrace.join("\n"))
  end
end

# Run the server with logging enabled (it's a separate thread).
server = SailsTelnetServer.new 1025, '0.0.0.0'
server.audit = true                  # Turn logging on.
server.debug = true                  # Turn debugging on.
server.start

# *** Now point telnet to localhost to see it working ***

sleep 10 until server.stopped?

# See if it's still running.
##GServer.in_service?(23)              # -> true
##server.stopped?                      # -> false

# Shut the server down gracefully.
##server.shutdown

# Alternatively, stop it immediately.
##GServer.stop(23)
# or, of course, "server.stop".
