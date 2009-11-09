require 'rubygems'
require 'hpricot'

require 'pp'
require 'yaml'

require 'sails'
include Sails

puts "Loading config"
begin
	config = YAML.load(File.open('sails.conf'))
rescue
	raise Sails::ProviderError, 'Could not read the sails.conf file. Make sure it exists and is proper YAML.'
end
provider = Provider.new config['domain-name'], config['service-name']

begin
	provider.connect_sock config['xmpp-connect-host'], config['xmpp-connect-port'].to_i
rescue
	raise Sails::ProviderError, 'Could not connect to the XMPP server.'
end

begin
	provider.load_certs config['certificate-chain']
	provider.load_key config['private-key-path']
rescue
	raise Sails::ProviderError, 'Could not read the certificate chain and/or private key. Make sure they are in the proper format.'
end

if config['ping']
	puts "Sending a ping to #{config['ping']} due to configoration."
	provider << Server.new(provider, config['ping'], config['ping'])
end

provider.send_data '<stream:stream xmlns="jabber:component:accept" xmlns:stream="http://etherx.jabber.org/streams" to="' + provider.name + '">'

doc = provider.read_plain
id = (doc/'stream:stream').first['id']

unless id
	error = (doc/'stream:error').first.children.first.name rescue nil
	message = case error
		when 'conflict': 'The XMPP server denied this component because it conflicts with one that is already connected.'
		when nil: 'Unable to connect to XMPP. The server denied the component for an unknown reason.'
		else; "Unable to connect to XMPP: #{error}"
	end
	raise ProviderError, message
end

key = Digest::SHA1.hexdigest(id + config['xmpp-password'])
provider.send_data "<handshake>#{key}</handshake>"

remote = SailsRemote.serve(provider)
puts "DRb server running at #{remote.uri}"

trap("INT") do
	remote.stop_service
	puts 'OBAI'
	exit
end

Thread.new do
	provider.send_data ' ' while sleep 60
end

puts 'Entering program loop'

ids = {} # used for history requests
until provider.sock.closed?
	packets = provider.read
	
	packets.each do |packet|
		name = packet.name
		
		if name == 'handshake'
			puts "Connected to XMPP."
			provider.ready! # flushes
			next
		end
		
		type = packet['type'] || 'none'
		id = packet['id']
		from = packet['from']
		to = packet['to']
		
		server = provider.find_or_create_server from
		
		case [name.to_sym, type.to_sym]
		
			when [:iq, :get]
			
				if (packet/'query').any?
					if (packet/'query').first['xmlns'].include?('items')
						provider.send_xml 'iq', id, from, "<query xmlns=\"http://jabber.org/protocol/disco#items\"><item jid=\"#{provider.name}\" name=\"#{config['identity']}\"/></query>"
					else
						provider.send_xml 'iq', id, from, "<query xmlns=\"http://jabber.org/protocol/disco#info\"><identity category=\"collaboration\" type=\"google-wave\" name=\"#{config['identity']}\"/><feature var=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></query>"
					end
					
				elsif (packet/'pubsub/items/delta-history').any?
					puts "#{from} requested some deltas"
					
					node = (packet/'pubsub/items/delta-history').first
					wave = provider.find_or_create_wave node['wavelet-name']
					
					payload = ''
					(node['start-version'].to_i..node['end-version'].to_i).each do |version|
						delta = wave[version]
						next unless delta.is_a? Delta
						payload << "<item><applied-delta xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"><![CDATA[#{encode64 delta.to_applied}]]></applied-delta></item>"
					end
					
					payload << "<item><commit-notice xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" version=\"#{wave[node['end-version'].to_i].version}\"/></item>"
					payload << "<item><history-truncated xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" version=\"#{wave[node['end-version'].to_i].version}\"/></item>"
					
					provider.send_xml 'iq', id, from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items>#{payload}</items></pubsub>"
					
				elsif (packet/'pubsub/items/signer-request').any?
					puts "#{from} requested a certificate"
					
					node = (packet/'pubsub/items/signer-request').first
					hash = decode64 node['signer-id']
					server = provider.servers.by_signer_id  hash

					if server
						puts "Sending a cert to #{from} on request, for #{server.domain}"
							
						payload = server.certificates64.map do |cert|
							"<certificate><![CDATA[#{cert}]]></certificate>"
						end.join ''
							
						provider.send_xml 'iq', id, from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items><signature xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" domain=\"#{server.certificates.first.subject['CN']}\" algorithm=\"SHA256\">#{payload}</signature></items></pubsub>"
					else
						puts 'Couldn\'t find the signer ID.' # TODO: Send error packet
					end
					
				end
				
			when [:iq, :set]
				if (packet/'certificate').any?
					node = (packet/'signature').first
					puts "Got a cert from for #{node['domain']}"
					
					server.domain = node['domain']
					server.certificates = (node/'certificate').map do |cert|
						cert.inner_text
					end
					
					remote.all_waves.each do |wave|
						wave.deltas.each_value do |delta|
							next unless delta.is_a? Delta
							delta.server = server if delta.signer_id == server.certificate_hash
							puts "Changed server for #{wave.conv_root_path} ##{delta.version}."
						end
					end
					
					provider.send_xml 'iq', id, from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish><item node=\"signer\"><signature-response xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></item></publish></pubsub>"
				
				elsif (packet/'publish').any?
					puts "Publish request from #{from} for one of my waves"
					node = (packet/'publish/item/submit-request/delta').first
					delta = Delta.parse(provider, node['wavelet-name'], decode64(node.inner_text))
					
					provider.send_xml 'message', id, from, "<received xmlns=\"urn:xmpp:receipts\"/>"
				end
				
			when [:iq, :result]
				if packet.to_s.include? '<query xmlns="http://jabber.org/protocol/disco#items" />'
					puts "#{from} is a FedOne server. Pulling details (state = :listing)"
					server.name = from
					server.domain = server.name.sub('wave.', '') if server.domain == server.name
					server.state = :listing
					provider.send_xml 'iq', 'get', from, '<query xmlns="http://jabber.org/protocol/disco#info"/>'
				
				elsif (packet/'query/item').any?
					puts "Got service listing from #{from}:"
					
					haswave = false
					(packet/'query/item').each do |item|
						puts "\t#{item['name']}\t(at #{item['jid']})"
						haswave = item['jid'] if item['name'].include? 'Wave Server'
					end
					
					if haswave
						server.name = haswave
						server.state = :listing
						
						puts "Found wave services on #{from} as #{haswave}, pulling details (state = :listing)"
						provider.send_xml 'iq', 'get', haswave, '<query xmlns="http://jabber.org/protocol/disco#info"/>'
					else
						puts "No wave server found on #{from}"
					end
				
				elsif (packet/'query/identity').any?
					node = (packet/'query/identity').first
					
					if node['type'] == 'google-wave'
						server.state = :details
						
						puts "#{from} is Google Wave service (#{node['name']}), sending ping (state = :details)"
						provider.send_xml 'message', 'normal', from, '<ping xmlns="http://waveprotocol.org/protocol/0.2/waveserver"/><request xmlns="urn:xmpp:receipts"/>'
					else
						puts "#{from} is NOT a Google Wave service, it's a \"#{node['name']}\"!"
					end
				
				elsif (packet/'signature/certificate').any?
					node = (packet/'signature').first
					puts "Got a cert from #{from} for #{node['domain']}"
					
					server = provider.find_or_create_server node['domain']
					
					server.domain = node['domain']
					server.certificates = (node/'certificate').map do |cert|
						cert.inner_text
					end
					
					remote.all_waves.each do |wave|
						wave.deltas.each_value do |delta|
							next unless delta.is_a? Delta
							delta.server = server if delta.signer_id == server.certificate_hash
							puts "Changed server for #{wave.conv_root_path} ##{delta.version}."
						end
					end
				
				elsif (packet/'pubsub/publish/item/signature-response').any?
					if server.state == :ponged
						server.state = :ready
						puts "#{from} ACK'ed my cert, now to flush the queue (state = :ready)"
						server.flush
						
					else
						puts "#{from} ACK'ed my cert."
					end
					
				elsif (packet/'pubsub/items/item/applied-delta').any?
					wave = ids[id]
					ids.delete id
					puts "Got history for #{wave.name}"
					
					(packet/'pubsub/items/item/applied-delta').each do |update|
						delta = Delta.parse(provider, wave.conv_root_path, decode64(update.inner_text), true)
						puts "Got a delta, version #{delta.version}"
					end
					
					wave.apply :newest
				end
			
			when [:message, :normal], [:message, :none]
				packet.children.each do |message|
					subtype = message.name
					if subtype == 'received'
						if server.state == :details
							server.state = :ponged
							puts "#{from} ponged, attempting to send my cert (state = :ponged)"
							
							payload = provider.local.certificates64.map do |cert|
								"<certificate><![CDATA[#{cert}]]></certificate>"
							end.join ''
							
							provider.send_xml 'iq', 'set', from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish node=\"signer\"><item><signature xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" domain=\"#{provider.name}\" algorithm=\"SHA256\">#{payload}</signature></item></publish></pubsub>"
						
						else
							puts "#{from} ACK'ed our previous packet."
						end
						
					elsif subtype == 'request'
					
						if (packet/'event/items/item/wavelet-update').any?
							wave = nil
							(packet/'event/items/item/wavelet-update').each do |update|
								next unless (update/'applied-delta').any?
								
								delta = Delta.parse(provider, update['wavelet-name'], decode64(update.inner_text), true)
								puts "Got delta version #{delta.version rescue -1}"
								wave = delta.wave if delta
							end
							
							wave.apply(:newest) if wave && wave.complete?(ids)
						end
						
						provider.send_xml 'message', 'normal', from, '<received xmlns="urn:xmpp:receipts"/>', id
						
					elsif subtype == 'ping'
						puts "Got a ping from #{from}"
					
					end
					
					
				end
				
			when [:iq, :error]
				if (packet/'remote-server-not-found').any?
				
					if "wave.#{server.domain}" == server.name
						puts "Already tried the wave. trick on #{from}. (state = :error)"
						server.state = :error
					else
						puts "Trying the wave. trick on #{from}. (state = :listing)"
						server.name = "wave.#{server.domain}"
						server.state = :listing
						provider.send_xml 'iq', 'get', server.name, '<query xmlns="http://jabber.org/protocol/disco#info"/>'
					end
					
				else
					puts 'ERROR!'
				end
			
			else
				puts "Unknown packet"
				
		end
	end
end
