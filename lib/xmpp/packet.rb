
module Sails
module XMPP
	class Packet
		attr_accessor :connection, :name, :type, :to, :from, :id, :node

		def initialize connection, xml
			@connection = connection
			@node = xml
			
			@name = xml.name
			@type = xml['type'] || 'default'
			@to   = xml['to']
			@from = xml['from']
			@id   = xml['id']
		end
		
		def respond data
			@connection.send @name, 'result', @from, data, @id
		end
	end
end
end
