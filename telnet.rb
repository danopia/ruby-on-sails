#!/usr/bin/env ruby

require 'core.rb'
require 'gserver'

#
# A server that connects people to wave.
#
class WaveServer < GServer
	def initialize(port=23, host='localhost', maxConnections = 20, *args)
		super(port, host, maxConnections, *args)
	end
	
	def serve(io)
		name = nil
		sock = nil
		
		while true
			line = sock ? io.gets.chomp : '/connect danopia'
			params = line.split ' '
			
			case params.first.downcase
				when '/quit'
					io.puts 'Bye!'
					return
				
				when '/connect'
					address = "#{params[1]}@danopia.net"
					io.puts "Connecting as #{address}...."
					
					sock = WaveSocket.new(address, 'localhost', 9876)
					sock.request_wave_list
					
					Thread.new do
						begin
							until sock.sock.closed?
								packet = sock.recv
								log "Got packet type #{packet.type}"
								
								case packet.type
									when 'waveserver.ProtocolWaveletUpdate'
										address = packet[0].first
										
										domain = nil
										id = nil
										
										domain = $1 if address =~ /^wave:\/\/([^\/]+)\//
										id = $1 if address =~ /(w\+[a-zA-Z0-9\-]+)/
										
										wave = sock.find_wave id
										unless wave
											log "Creating a new wave entry for #{domain}!#{id}"
											wave = Wave.new id, domain
											sock.waves << wave
											
											redraw(io, sock) if address.include? '!indexwave'
										end
										
										if address.include? '!indexwave'
											log "Requesting more details on #{wave.id}"
											sock.request_wave wave
										else
										
											log "Got info on wave: #{id}"
											
											if wave.revisions.any?
												log "Overwriting existing entry"
												wave.participants.clear
												wave.revisions.clear
												wave.messages.clear
											end
											
											packet[1].each do |update|
												rev = Revision.new wave, update[0].first, update[1].first
												
												update = update[2].first
												rev.added_participants = update[0] if update[0]
												rev.removed_participants = update[1] if update[1]
												
												p update
												if update[2]
													# {2 => [{
													# 	0 => ["main"],
													# 	1 => [{
													# 		0 => [{
													# 			2 => [{
													# 				0 => ["line"],
													# 				1 => [{
													# 					0 => ["by"],
													# 					1 => ["test@danopia.net"]
													# 				}]
													# 			}]},
													# 			" \001",
													# 			{
													# 				1 => ["hi"]
													# 			}
													# 		]}
													# 	]}
													# ]}

													update = update[2].first[1].first[0]
													message = update.select{|thing|thing.is_a? Hash}.last[1].first
													rev.deltas << message
													wave.messages << [rev.author, message]
												end
												
												wave.revisions << rev
											end
											
											redraw io, sock
										end
										
									else
										log "Unknown packet #{packet.type}"
								end
								
							end
						rescue => error
							io.puts 'Socket error'
							p error
						end
					end
					
			end
			
		end
	end
	
	def redraw(io, sock)
		io.print `clear`
		io.puts 'Waves:'
		sock.waves.each do |wave|
			io.puts ' ---+---------------------------------------------------'
			
			if wave.messages.any?
				io.puts "  #{sock.waves.index wave} |\t#{wave.id}\t<#{wave.messages.first[0]}> #{wave.messages.first[1]}"
				(wave.messages.size - 1).times do |index|
					io.puts "    |\t\t\t<#{wave.messages[index+1][0]}> #{wave.messages[index+1][1]}"
				end
			else
				io.puts "  #{sock.waves.index wave} |\t#{wave.id}\t*waiting*"
			end
		end
		
		io.puts ' ---+---------------------------------------------------' if sock.waves.any?
	end
	
	def error(detail)
		log(detail.inspect)
    log(detail.backtrace.join("\n"))
  end
end

# Run the server with logging enabled (it's a separate thread).
server = WaveServer.new 1025, '0.0.0.0'
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
