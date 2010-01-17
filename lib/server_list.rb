
module Sails

# Variation of Hash with a degree of case-insensitive keys.
class ServerList < Hash
	attr_accessor :provider
	
	def initialize provider=nil
		super()
		@provider = provider
	end
	
	def [](server)
		return nil unless server
		super server.downcase
	end
	def []=(name, server)
		return nil unless name
		super name.downcase, server
	end
	
	def delete server
		return nil unless server
		super server.downcase
	end
	
	def << server
		self[server.domain] = server
		self[server.jid] = server
	end
	
	def by_signer_id hash
		server = values.find{|server| server.certificate_hash == hash}
		return server if server
		
		record = ::Server.find_by_signer_id Utils.encode64(hash)
		server = Server.new @provider, record.domain if record
		
		server
	end
end # class

end # module
