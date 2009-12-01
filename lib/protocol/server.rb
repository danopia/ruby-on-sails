require File.join(File.dirname(__FILE__), 'json_connection')
require File.join(File.dirname(__FILE__), 'server_client')

module Sails
module Protocol

class Server < JsonConnection
	attr_accessor :name, :client, :provider
	
  def initialize provider
    super()
    @provider = provider
  end
  
  def send_wave_list amount=50, page=1 # TODO: Use the limits
    waves = @provider.servers.values.uniq.map {|server| server.waves.keys}.flatten
    send_object 'wave_list', {'wave_ids' => waves}
  end
  
  def send_wave_info wave
    blips = {}
    wave.blips.each_pair do |id, blip|
      blips[id] = blip.digest
    end
    
    send_object 'wave_info', {
      'id' => wave.name,
      'version' => wave.newest_version,
      'participants' => wave.participants.map {|user| user.to_s},
      'blips' => blips
    }
  end
  
  def got_object action, data
    case action
      when 'login'
        @client = ServerClient.login data['user'], data['pass'], self
        if @client
          puts "#{@client.address} logged in (#{data['pass']})."
          send_object 'login', {'username' => @client.username, 'address' => @client.address}
          send_wave_list
        else
          puts "Bad login from #{@ip}:#{@port}... #{data['user']}:#{data['pass']}"
        end
        
      when 'wave_info'
        data['wave_ids'].each do |id|
          send_wave_info @provider[id]
        end
        
      else
        p data
		end
  end
end # class
end # module
end # module
