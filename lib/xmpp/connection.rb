require 'rubygems'
require 'eventmachine'
require 'socket'
require 'hpricot'

module Sails
module XMPP
	class Connection < EventMachine::Connection
		def self.connect host, port, *args
			p host, port
			EventMachine::connect host, port, self, *args
		end
		def self.start_loop *args
			EventMachine::run { self.connect *args }
		end
		
		def self.on_packet &blck
			@@handler = blck
		end

		def self.random_packet_id
			"#{rand(9999)}-#{rand(99)}"
		end
		
		def self.send *args
			@@instance.send *args
		end
		def send name, type, to, data, id=nil
			send_raw "<#{name} type=\"#{type}\" id=\"#{id||Connection.random_packet_id}\" to=\"#{to}\" from=\"#{me}\">#{data}</#{name}>"
		end
		
		def self.send_raw data
			@@instance.send_raw data
		end
		def send_raw data
			data = data.to_s
			puts ">> #{data}"
			send_data "#{data}\n"
		end
		
		def initialize
			super
			
			begin
				@port, @ip = Socket.unpack_sockaddr_in get_peername
				puts "Connected to XMPP at #{@ip}:#{@port}"
			rescue TypeError
				puts "Unable to determine endpoint (connection refused?)"
			end
			
			@buffer = ''
			@@instance = self
		end
		
		def receive_data data
			@buffer << data
			return unless @buffer[-1,1] == '>' || @buffer[-1,1] == "\n"
			puts "<< #{@buffer}"
			if @@handler
				doc = Hpricot "<root>#{@buffer}</root>"
				doc.root.children.each do |node|
					unless node.is_a? Hpricot::XMLDecl
						packet = Packet.new self, node
						receive_object packet, node
					end
				end
			end
			@buffer = ''
		end
		
		def receive_object packet, node
			@@handler.call self, packet, node
		end
		
		def unbind
			puts "Disconnected from XMPP, reconnecting in 5 seconds"
			
   		EventMachine::add_timer 5 do
   			EventMachine.next_tick { self.class.connect @ip, @port }
			end
		end
	end
end
end
