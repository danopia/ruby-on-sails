require 'rubygems'
require 'eventmachine'
require 'socket'
require 'json'

module Sails
module Protocol

class JsonConnection < EventMachine::Connection
	attr_accessor :port, :ip
	INSTANCES = []
	
  def initialize
    INSTANCES << self
  end
  
  def connection_completed
    @port, @ip = Socket.unpack_sockaddr_in get_peername
    puts "connection from #{@ip}:#{@port}"
  end
  
  def post_init
    @buffer = ''
  end

  def receive_data data
    @buffer += data
    while @buffer.include? "\n"
    	line = @buffer.slice!(0, @buffer.index("\n")+1).chomp
			data = JSON.parse line
			action = data['action']
			got_object action, data
    end
  end
  
  def got_object action, data
  end
  
  def send_object action, data
    data['action'] = action
    send_data data.to_json + "\n"
  end
  
  def unbind
  	puts "connection closed from #{@ip}:#{@port}"
  end
end # class
end # module
end # module
