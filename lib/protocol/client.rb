require File.join(File.dirname(__FILE__), 'json_connection')

module Sails
module Protocol

class Client < JsonConnection
  attr_accessor :username, :address, :waves
  
  def self.connect *args
		EM.connect "127.0.0.1", 7849, self, *args
	end
  def self.start_loop *args
		EM.run { connect *args }
	end
  
  def initialize username=nil, password=nil
    super()
    login username, password if username && password
  end
  
  def post_init
  	super
  	@waves = {}
  end
  
  def login username, password
    send_object 'login', {'user' => username, 'pass' => password}
  end
  
  def request_wave_info wave_ids
    wave_ids = [wave_ids] unless wave_ids.is_a? Array
    send_object 'wave_info', {'wave_ids' => wave_ids}
  end
  
  def got_object action, data
    case action
      when 'login'
        @username = data['username']
        @address = data['address']
        logged_in
        
      when 'wave_list'
      	got_wave_list data['wave_ids']
        
      when 'wave_info'
        got_wave_info data['id'], data['version'], data['participants'], data['blips']
        
      else
        p data
    end
  end
  
  
  
  def logged_in
  	puts "Logged in."
  end
  
  def got_wave_list wave_ids
		puts "Got list of waves:", wave_ids
  	request_wave_info wave_ids
  end
  
  def got_wave_info wave_id, version, participants, blips
  	@waves[wave_id] = {
  		:version => version,
  		:participants => participants,
  		:blips => blips
  	}
  	puts "Got info for wave #{wave_id}"
  end
end # class

end # module
end # module
