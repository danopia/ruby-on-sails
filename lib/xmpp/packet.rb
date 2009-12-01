
module Sails
module XMPP
	class Packet
		attr_accessor :connection, :name, :type, :to, :from, :id, :node, :server

		def initialize connection, xml
			@connection = connection
			@node = xml
			
			@name = xml.name
			@type = xml['type'] || 'default'
			@to   = xml['to']
			@from = xml['from']
			@id   = xml['id']
			
			if @from == @connection.jid || @from.nil?
				@server = @connection.local
			elsif @connection.servers.keys.include? @from.downcase
				@server = @connection.servers[@from]
			else
				@server = @connection.servers.values.find {|server| server.jids.include? @from}
				@server ||= Server.new @connection, @from
			end
		end
		
		def respond data
			@connection << [@name, 'result', @from, data, @id]
		end
	end
end
end
