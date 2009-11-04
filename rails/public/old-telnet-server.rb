#!/usr/bin/env ruby

require 'gserver'

#
# A server that connects people to wave.
#
class WaveServer < GServer
	def initialize(port=23, host='localhost', maxConnections = 20, *args)
		super(port, host, maxConnections, *args)
	end
	
	def serve(io)
		io.putc 255
		io.putc 253
		io.putc 31
		
		oldmode = 0
		mode = 0
		width = 80
		height = 25
		name = ''
		
		stdin = nil
		stdout = nil
		stderr = nil
		
		while true
			char = nil
			begin
				char = io.read_nonblock(1)
			rescue Errno::EAGAIN => ex
				sleep 0.1
			end
			
			if char
				char = char[0]
				#$stdout.puts char
			end
			
			if !char && mode == -2
			
				begin
					while true
						output = stdout.read_nonblock 1024
						#p output
						output.gsub! "\e[u", "\r"
						io.print output
					end
				rescue Errno::EAGAIN => ex
				end
			
			elsif !char # ignore
			
			elsif mode == -1
				require 'open3'
				stdin, stdout, stderr = Open3.popen3 "./run-client-console.sh #{name}"
				stdin.puts
				mode = -2
				oldmode = -2
				
			elsif char == 255
				mode = 1
			elsif mode == 1 && char == 250
				mode = 1.5
			elsif mode == 1 && char >= 251 && char <= 254
				mode = 1.75
			elsif mode == 1.5 && char == 31
				mode = 2
			elsif mode == 2 && char == 0
				mode = 3
			elsif mode == 3
				width = char
				mode = 4
			elsif mode == 4 && char == 0
				mode = 5
			elsif mode == 5 && oldmode == 0
				height = char
				
				io.print "\e[H\e[2J"
				motd = <<EOF
 #####  ####### #######  #####  #       #######
#     # #     # #     # #     # #       #
#       #     # #     # #       #       #
#  #### #     # #     # #  #### #       #####
#     # #     # #     # #     # #       #
#     # #     # #     # #     # #       #
 #####  ####### #######  #####  ####### #######

        #     #    #    #     # #######
        #  #  #   # #   #     # #
        #  #  #  #   #  #     # #
        #  #  # #     # #     # #####
        #  #  # #######  #   #  #
        #  #  # #     #   # #   #
         ## ##  #     #    #    #######
EOF
				
				motd_width = motd.split("\n").map{|line|line.size}.max
				padding = ' ' * ((width - motd_width) / 2)
				motd.split("\n").each do |line|
					io.puts padding + line
				end
				
				io.puts
				io.puts 'Please enter your name. This was a simple hacky username'
				io.puts 'prompt interface, so no backspacing. yet.'
				io.puts
				io.puts 'Leave blank to disconnect.'
				io.puts
				io.print '> ' + name
				 
				mode = 0
			elsif mode > 0
				mode = oldmode
				
			elsif char == 13 # Ignore
			elsif mode == -2 # send client intput to wave
				stdin.putc char
				
			elsif char == 10 # Connect
			
				if name.empty?
					io.print "\e[H\e[2J"
					io.puts 'Bye.'
					return
				end
				
				io.print "\e[H\e[2J"
				motd = <<EOF
 #####  ####### #######  #####  #       #######
#     # #     # #     # #     # #       #
#       #     # #     # #       #       #
#  #### #     # #     # #  #### #       #####
#     # #     # #     # #     # #       #
#     # #     # #     # #     # #       #
 #####  ####### #######  #####  ####### #######

        #     #    #    #     # #######
        #  #  #   # #   #     # #
        #  #  #  #   #  #     # #
        #  #  # #     # #     # #####
        #  #  # #######  #   #  #
        #  #  # #     #   # #   #
         ## ##  #     #    #    #######
EOF
				
				motd_width = motd.split("\n").map{|line|line.size}.max
				padding = ' ' * ((width - motd_width) / 2)
				motd.split("\n").each do |line|
					io.puts padding + line
				end
				
				io.puts
				io.puts "Hey, #{name}!"
				io.puts "Your Wave address is <#{name}@danopia.net>"
				io.puts "This server is not federated yet so only internal messages work."
				io.puts
				io.puts "I'll connect you to Google Wave in a second."
				
				addr = io.peeraddr
				log "#{self.class.to_s} #{addr[2]}<#{addr[3]}> Authed as #{name}"
				
				mode = -1
				io.puts
				5.times do
					io.print '.'
					sleep 0.1
				end
				io.ungetc 10
			else
				name << char
				io.print "\r> #{name}"
			end
			
			#sleep 0.1
		end
	end
	
	def error(detail)
		log(detail.inspect)
    log(detail.backtrace.join("\n"))
  end
end

# Run the server with logging enabled (it's a separate thread).
server = WaveServer.new 23, '0.0.0.0'
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
