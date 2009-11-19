module Sails

class WaveUser
	attr_accessor :username, :server, :account, :provider
	
	def initialize provider, address
		provider = provider.remote if provider.is_a? Remote
		@provider = provider
		
		@username, domain = address.downcase.split '@', 2
		if domain == @provider.domain
			@account = User.find_by_login @username
			@server = @provider.local
		else
			@server = @provider.find_or_create_server domain
		end
		
		@server << self
	end
	
	def local?
		@server == @provider.local
	end
	
	def address
		"#{@username}@#{server.domain}"
	end
	alias to_s address
	
	def gravatar size=80
		if @account
			User.gravatar @account.email, size
		else
			User.gravatar address, size
		end
	end
	
	def display_name
		if @account
			@account.public_name
		else
			address
		end
	end
	
	def to_html size=25
		img = ''
		img = "<img src=\"#{gravatar size}\" /> " unless size.nil?
		
		if local?
			"#{img}<a href=\"/users/#{username}\">#{display_name}</a>"
		else
			"#{img}#{address}"
		end
	end

	
end # class

end # module
