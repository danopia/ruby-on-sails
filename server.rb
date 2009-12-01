require 'rubygems'
require 'eventmachine'
require 'socket'
require 'json'

module Sails2

class Client
  attr_accessor :username, :address, :record, :server, :connected_at, :last_action
  
  def initialize record, server=nil,a=nil,b=nil # TODO: Database
    @username = a#record.login
    @address = b#record.address
    @record = record
    @server = server
    @connected_at = Time.now
    @last_action = Time.now
  end
  
  def self.check_login username, password
    %w{danopia test osirisx loonacy l3reak eggy}.include?(username) &&
    %W{password password1 12345678 test}.include?(password)
  end
  
  def self.login username, password, server=nil
    if check_login username, password
      Client.new nil, server, username, "#{username}@danopia.net"
    else
      nil # TODO: Raise error
    end
  end
end

class Server < EventMachine::Connection
	attr_accessor :port, :ip, :name, :client, :provider
	INSTANCES = []
	
  def initialize provider
    @provider = provider
    @buffer = ''
    #@clients = []
    
    INSTANCES << self
    
    sleep 0.2
    @port, @ip = Socket.unpack_sockaddr_in get_peername
    puts "connection from #{@ip}:#{@port}"
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
  
  def send_wave_list amount=50, page=1 # TODO: Use limits
    waves = @provider.servers.values.uniq.map {|server| server.waves.keys}.flatten
    send_object 'wavelist', {'wave_ids' => waves}
  end
  
  def got_line line
		data = JSON.parse line
    action = data['action']
    
    case action
      when 'login'
        @client = Client.login data['user'], data['pass'], self
        if @client
          puts "#{@client.address} logged in (#{data['pass']})."
          send_object 'loggedin', {'username' => @client.username, 'address' => @client.address}
          send_wave_list
        else
          puts "Bad login from #{@ip}:#{@port}... #{data['user']}:#{data['pass']}"
        end
        
      when 'wave_info'
        wave = @provider[data['wave_id']]
        puts wave.inspect[0,100]
        
        blips = {}
        wave.blips.each_pair do |id, blip|
          blips[id] = blip.digest
        end
        
        send_object 'wave_info', {
          'id' => wave.name,
          'participants' => wave.participants.map {|user| user.to_s},
          'blips' => blips
        }
		end
  end
  
  def unbind
  	puts "connection closed from #{@ip}:#{@port}"
  	INSTANCES.delete self
  end
end # class
end # module

#EM.run do
#  EM.start_server "127.0.0.1", 7849, Sails::Server
#  puts "server started"
#end
