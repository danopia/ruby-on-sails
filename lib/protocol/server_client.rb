module Sails
module Protocol

class ServerClient
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
      self.new nil, server, username, "#{username}@danopia.net"
    else
      nil # TODO: Raise error
    end
  end
end # class
end # module
end # module
