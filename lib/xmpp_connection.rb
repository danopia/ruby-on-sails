require 'rubygems'
require 'eventmachine'
require 'socket'
require 'hpricot'

module Sails
	class XMPPConnection < EventMachine::Connection
		def self.connect host, port, *args
			EventMachine::connect host, port, self, *args
		end
		def self.start_loop *args
			EventMachine::run { self.connect *args }
		end
		
		def self.on_packet &blck
			@@handler = blck
		end
		def self.send data
			@@instance.send data
		end
		
		def initialize jid
			super
			begin
				@port, @ip = Socket.unpack_sockaddr_in get_peername
				puts "Connected to XMPP at #{@ip}:#{@port}"
			rescue TypeError
				puts "Unable to determine endpoint (connection refused?)"
			end
			
			@jid = jid
			@buffer = ''
			@@instance = self
			
			start_auth
		end
		
		def start_auth
			send "<stream:stream xmlns=\"jabber:component:accept\" xmlns:stream=\"http://etherx.jabber.org/streams\" to=\"#{@jid}\">"
		end
		
		def receive_data data
			puts "<< #{data}"
			if @@handler
				doc = Hpricot "<root>#{data}</root>"
				doc.root.children.each do |node|
					@@handler.call node unless node.is_a? Hpricot::XMLDecl
				end
			end
			
			#~ @buffer += data
			#~ ...
			#~ while @buffer.include? "\n"
				#~ packet = @buffer.slice!(0, @buffer.index("\n")+1).chomp
				#~ data = Hpricot packet
				#~ @@handler.call data if @@handler && hash.has_key?('data')
			#~ end
		end
		
		def send data
			data = data.to_s
			puts ">> #{data}"
			send_data "#{data}\n"
		end
		
		def unbind
			puts "Disconnected from XMPP, reconnecting in 5 seconds"
			
   		EventMachine::add_timer 5 do
   			EventMachine.next_tick { self.class.connect @ip, @port }
			end
		end
	end
end
