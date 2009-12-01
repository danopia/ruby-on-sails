require 'rubygems'
require 'eventmachine'
require 'socket'
require 'json'

module Sails

class ClientConnection < EventMachine::Connection
  attr_accessor :port, :ip, :username, :address
  
  def initialize username, password
    super
    
    send_object 'login', {'user' => username, 'pass' => password}
    
    sleep 0.2
    @port, @ip = Socket.unpack_sockaddr_in get_peername
    puts "connected to #{@ip}:#{@port}"
    @buffer = ''
  end
  
  def request_wave_info wave_id
    send_object 'wave_info', {'wave_id' => wave_id}
  end

  def receive_data data
    @buffer += data
    while @buffer.include? "\n"
    	got_line @buffer.slice!(0, @buffer.index("\n")+1).chomp
    end
  end
  
  def send_object action, hash
    hash['action'] = action
    send_data hash.to_json + "\n"
  end
  
  def got_line line
		data = JSON.parse line
		
    action = data['action']
    case action
      when 'loggin'
        puts "Logged in."
        @username = data['username']
        @address = data['address']
        
      when 'wavelist'
        puts "Got list of waves:"
        puts data['wave_ids']
        data['wave_ids'].each do |id|
          request_wave_info id
        end
        
      else
        p data
    end
  end
  
  def unbind
  	puts "connection closed to #{@ip}:#{@port}"
  end
end # class
end # module

EM.run do
  EM.connect "127.0.0.1", 7849, Sails::ClientConnection, 'danopia', 'test'
end
