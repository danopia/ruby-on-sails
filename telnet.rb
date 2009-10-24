#!/usr/bin/env ruby

require 'gserver'
require 'wave.danopia.net/lib/sails_remote'

class SailsTelnetServer < GServer
	def initialize(port=23, host='localhost', maxConnections = 20, *args)
		super(port, host, maxConnections, *args)
		@remote = SailsRemote.connect
	end
	
	def serve(io)
		name = nil
		
		while true
			line = name ? io.gets.chomp : '/connect test'
			params = line.split ' '
			next if params.empty?
			
			case params.first.downcase
				when '/quit'
					io.puts 'Bye!'
					return
				
				when '/connect'
					name = params[1]
					address = "#{name}@#{remote.provider.domain}"
					io.puts "Connecting as #{address}...."
					
					redraw io
			end
			
		end
	end
	
	def redraw(io)
		io.print `clear`
		if @remote.waves.any?
			io.puts 'Waves:'
			i = 0
			@remote.waves.each_value do |wave|
				io.puts ' ---+---------------------------------------------------'
				io.puts "  #{i} |\t#{wave.name}@#{wave.host}"#\t<#{wave[0].author}> #{wave[0].operations.first}"
				wave.real_deltas.each do |delta|
					io.puts "    |\t\t\t<#{delta.author}> #{delta.operations.first.to_s}"
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
