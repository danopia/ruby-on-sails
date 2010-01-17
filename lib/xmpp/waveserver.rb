
module Sails
module XMPP
class WaveServer < Component
	attr_accessor :servers, :local
	
	def initialize config
		super

		@servers = ServerList.new self

		@local = Server.new self, @domain, @subdomain, false
		@local.state = :local
		
		load_certs_and_key
	#rescue => e
		#puts e.class, e.message, e.backtrace
	end
	
	def load_certs_and_key
		load_certs @config['certificate-chain']
		load_key @config['private-key-path']
	rescue Errno::ENOENT => e
		puts "Error while loading certificate chain and private key (did you make them?):"
		puts e.message
		EventMachine.stop_event_loop # hehe
	end
	
	# Load the provider's certificate from a file.
	def load_certs(paths)
		@local.certificates = paths.map {|path| open(path).read }
	end
	
	# Load the provider's private key from a file.
	def load_key(path)
		@key = OpenSSL::PKey::RSA.new(open(path).read)
	end
	
	# Signs a chunk of data using the private key.
	def sign data
		@key.sign OpenSSL::Digest::SHA1.new, data
	end
	
	# Look up a wave.
	#
	# Can be passed in domain/w+name format for a certain wave, or name format
	# to search all known waves.
	def [](name)
		if name =~ /^(.+)\/w\+(.+)$/
			server = @servers[$1]
			return nil unless server
			server[$2]
		else
			# allow fallback to not specifing a domain

			@servers.values.each do |server|
				return server[name] if server[name]
			end
			
			nil
		end
	end
	
	# Add a wave to the correct server -or- Add a server to the main list
	def << item
		if item.is_a? Server
			@servers[item.domain] = item
			init_server item
		
		elsif item.is_a? Wave
			(item.server || @local) << item
			
		else
			super # for packets
		end
	end
	
	def all_waves
    waves = @servers.values.uniq.map {|server| server.waves.values}.flatten
  end
	
	# Flush all the remote servers.
	def flush
		return unless ready?
		
		super # flush self
		
		@servers.each_value do |server|
			if server.state != :uninited
				server.flush
			end
		end
	end
	
	def find_or_create_wave path
		domain, name, wavelet = Utils.parse_wavelet_address path
		
		server = find_or_create_server domain
		return server[name] if server[name]
		
		wave = Wave.new self, name, server
		self << wave
		wave
	end
	
	def find_or_create_server name
		if @servers.keys.include? name.downcase
			@servers[name]
		else
			Server.new self, name
		end
	end
	
	def find_or_create_user address
		return address if address.is_a? WaveUser
		
		username, domain = address.downcase.split '@', 2

		server = find_or_create_server domain
		
		return server.users[username] if server.users[username]
		WaveUser.new self, address
	end
	
	
	handle 'iq', 'get' do |conn, packet, xml|
		if (xml/'query').any?
			if (xml/'query').first['xmlns'].include? 'items'
				packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#items\"><item jid=\"#{conn.jid}\" name=\"#{conn.config['identity']}\"/></query>"
			else
				packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#info\"><identity category=\"collaboration\" type=\"ruby-on-sails\" name=\"#{conn.config['identity']}\"/><feature var=\"http://waveprotocol.org/protocol/0.2/waveserver\"/><feature var=\"http://jabber.org/protocol/disco#items\"/><feature var=\"http://jabber.org/protocol/disco#info\"/></query>"
			end
		elsif (xml/'pubsub/items/delta-history').any?
			puts "#{packet.from} requested some deltas"
			
			node = (xml/'pubsub/items/delta-history').first
			wave = conn.find_or_create_wave node['wavelet-name']
			wave.boom = true if wave.deltas.size == 1 && wave.local?
			
			payload = ''
			unless wave.boom
				version = node['start-version'].to_i
				until version > node['end-version'].to_i
					delta = wave[version]
					version = delta.version
					if delta.is_a? Delta
						payload << "<item><applied-delta xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"><![CDATA[#{Utils.encode64 delta.to_applied}]]></applied-delta></item>"
					end
					version += 1
				end
				
				payload << "<item><commit-notice xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" version=\"#{delta.version}\"/></item>"
				#if wave.newest_version > delta.version
					payload << "<item><history-truncated xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" version=\"#{delta.version}\"/></item>"
				#end
			end
			
			packet.respond "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items>#{payload}</items></pubsub>"
			
		elsif (xml/'pubsub/items/signer-request').any?
			puts "#{packet.from} requested a certificate"
			
			node = (xml/'pubsub/items/signer-request').first
			hash = Utils.decode64 node['signer-id']
			server = conn.servers.by_signer_id hash

			if server
				puts "Sending a cert to #{packet.from} on request, for #{server.domain}"
					
				packet.respond "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items><signature xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" domain=\"#{server.certificates.first.subject['CN']}\" algorithm=\"SHA256\">#{server.certificate_xml}</signature></items></pubsub>"
			else
				puts 'Couldn\'t find the signer ID.' # TODO: Send error packet
			end
			
		end
	end
	
	handle 'iq', 'result' do |conn, packet, xml|
		if (xml/'query').any?
			if (xml/'query[@xmlns=http://jabber.org/protocol/disco#items]').any?
				puts "Got service listing from #{packet.from}, inviting the services to a disco party"
				# at danopia's house, of course (i have a disco ball)
				packet.server.jids = (xml/'item').map {|node| node['jid']}
				packet.server.disco_jids
			else
				node = (xml/'query/identity').first
				
				if (xml/'feature[@var=http://waveprotocol.org/protocol/0.2/waveserver]').any?
					puts "#{packet.from} is Google Wave service (#{node['name']}), sending ping (state = :details)"
					packet.server.jid = packet.from
				else
					puts "#{packet.from} does not have the Google Wave feature."
				end
			end
		
		elsif (xml/'signature/certificate').any?
			node = (xml/'signature').first
			puts "Got a cert from #{packet.from} for #{node['domain']}"
			
			server = conn.find_or_create_server node['domain']
			
			server.domain = node['domain']
			server.certificates = (node/'certificate').map do |cert|
				cert.inner_text
			end
			
			conn.all_waves.each do |wave|
				wave.deltas.each_value do |delta|
					next unless delta.is_a? Delta
					delta.server = server if delta.signer_id == server.certificate_hash
					puts "Changed server for #{wave.conv_root_path} ##{delta.version}."
				end
			end
		
		elsif (xml/'pubsub/publish/item/signature-response').any?
			if packet.server.state == :ponged
				puts "#{packet.from} ACK'ed my cert, now to flush the queue (state = :ready)"
				packet.server.ready!
				
			else
				puts "#{packet.from} ACK'ed my cert."
			end
			
		elsif (xml/'pubsub/items/item/applied-delta').any?
			packet.id =~ /^100-(.+)$/
			if $1 && conn[$1]
				wave = conn[$1]
				puts "Got history for #{wave.name}"
				
				(xml/'pubsub/items/item/applied-delta').each do |update|
					delta = Delta.parse(conn, wave.conv_root_path, Utils.decode64(update.inner_text), true)
					puts "Got a delta, version #{delta.version}"
				end
				
				wave.apply :newest
			else
				puts "I didn't request this?"
			end
		end
	end
	
	handle 'iq', 'set' do |conn, packet, xml|
		if (xml/'certificate').any?
			node = (xml/'signature').first
			puts "Got a cert from #{node['domain']}"
			
			packet.server.domain = node['domain']
			packet.server.certificates = (node/'certificate').map do |cert|
				cert.inner_text
			end
			
			conn.all_waves.each do |wave|
				wave.deltas.each_value do |delta|
					next unless delta.is_a? Sails::Delta
					next unless delta.signer_id == packet.server.certificate_hash
					next if delta.server == packet.server
					delta.server = packet.server
					puts "Changed server for #{wave.conv_root_path} ##{delta.version}."
				end
			end
			
			packet.respond "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish><item node=\"signer\"><signature-response xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></item></publish></pubsub>"
		
		elsif (xml/'publish').any?
			puts "Publish request from #{packet.from} for one of my waves"
			node = (xml/'publish/item/submit-request/delta').first
			p decode64(node.inner_text)
			delta = Sails::Delta.parse(provider, node['wavelet-name'], Sails::Utils.decode64(node.inner_text))
			
			packet.respond "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish><item><submit-response xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" application-timestamp=\"#{delta.time}\" operations-applied=\"#{delta.operations.size}\"><hashed-version history-hash=\"#{Sails::Utils.encode64 delta.hash}\" version=\"#{delta.version}\"/></submit-response></item></publish></pubsub>"
		end
	end
	
	handle 'message', 'normal' do |conn, packet, xml|
		xml.children.each do |message|
			subtype = message.name
			if subtype == 'received'
				if packet.server.state == :details
					packet.server.state = :ponged
					puts "#{packet.from} ponged, attempting to send my cert (state = :ponged)"
					
					conn.send 'iq', 'set', packet.from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish node=\"signer\"><item><signature xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" domain=\"#{conn.domain}\" algorithm=\"SHA256\">#{conn.local.certificate_xml}</signature></item></publish></pubsub>"
				
				else
					puts "#{packet.from} ACK'ed our previous packet."
				end
				
			elsif subtype == 'request'
			
				if (xml/'event/items/item/wavelet-update').any?
					wave = nil
					(xml/'event/items/item/wavelet-update').each do |update|
						next unless (update/'applied-delta').any?
						
						delta = Delta.parse(conn, update['wavelet-name'], Utils.decode64(update.inner_text), true)
						puts "Got delta version #{delta.version rescue -1}"
						wave = delta.wave if delta
					end
					
					wave.apply(:newest) if wave && wave.complete?(true)
				end
				
				conn.send 'message', 'normal', packet.from, '<received xmlns="urn:xmpp:receipts"/>', packet.id
				
			elsif subtype == 'ping'
				puts "Got a ping from #{packet.from}"
			
			end
		end
	end
	
	handle 'iq', 'error' do |conn, packet, xml|
		if (xml/'remote-server-not-found').any?
		
			if "wave.#{packet.server.domain}" == packet.server.name
				puts "Already tried the wave. trick on #{packet.from}. (state = :error)"
				packet.server.state = :error
			else
				puts "Trying the wave. trick on #{packet.from}. (state = :listing)"
				packet.server.name = "wave.#{packet.server.domain}"
				packet.server.state = :listing
				packet.server.disco 'info'
			end
			
		else
			puts 'ERROR!'
		end
	end

end # waveserver
end # xmpp
end # sails
