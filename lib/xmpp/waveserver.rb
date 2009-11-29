module Sails
module XMPP
class WaveServer < Component
	handle 'iq', 'get' do |conn, packet, xml|
		if (xml/'query').any?
			if (xml/'query').first['xmlns'].include? 'items'
				packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#items\"><item jid=\"#{packet.connection.jid}\" name=\"#{conn.config['identity']}\"/></query>"
			else
				packet.respond "<query xmlns=\"http://jabber.org/protocol/disco#info\"><identity category=\"collaboration\" type=\"ruby-on-sails\" name=\"#{conn.config['identity']}\"/><feature var=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></query>"
			end
		elsif (xml/'pubsub/items/delta-history').any?
			puts "#{packet.from} requested some deltas"
			
			node = (xml/'pubsub/items/delta-history').first
			wave = provider.find_or_create_wave node['wavelet-name']
			wave.boom = true if wave.deltas.size == 1 && wave.local?
			
			payload = ''
			unless wave.boom
				version = node['start-version'].to_i
				until version > node['end-version'].to_i
					delta = wave[version]
					version = delta.version
					if delta.is_a? Sails::Delta
						payload << "<item><applied-delta xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"><![CDATA[#{Sails::Utils.encode64 delta.to_applied}]]></applied-delta></item>"
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
			hash = decode64 node['signer-id']
			server = provider.servers.by_signer_id hash

			if server
				puts "Sending a cert to #{packet.from} on request, for #{server.domain}"
					
				payload = server.certificates64.map do |cert|
					"<certificate><![CDATA[#{cert}]]></certificate>"
				end.join ''
					
				packet.respond "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items><signature xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" domain=\"#{server.certificates.first.subject['CN']}\" algorithm=\"SHA256\">#{payload}</signature></items></pubsub>"
			else
				puts 'Couldn\'t find the signer ID.' # TODO: Send error packet
			end
			
		end
	end
	
	handle 'iq', 'result' do |conn, packet, xml|
		if (xml/'query').any?
			if (xml/'query').first['xmlns'].include? 'items'
				puts "Got service listing from #{packet.from}:"
				(xml/'item').each do |node|
					conn.send 'iq', 'get', node['jid'], "<query xmlns=\"http://jabber.org/protocol/disco#info\" />"
				end
			else
				node = (xml/'query/identity').first
				
				if (xml/'feature[@var=http://waveprotocol.org/protocol/0.2/waveserver]').any?
					server.state = :details
					puts "#{packet.from} is Google Wave service (#{node['name']}), sending ping (state = :details)"
					conn.send 'message', 'normal', packet.from, '<ping xmlns="http://waveprotocol.org/protocol/0.2/waveserver"/><request xmlns="urn:xmpp:receipts"/>'
				else
					puts "#{packet.from} does not have the Google Wave feature."
				end
			end
		
		elsif (xml/'signature/certificate').any?
			node = (xml/'signature').first
			puts "Got a cert from #{from} for #{node['domain']}"
			
			server = provider.find_or_create_server node['domain']
			
			server.domain = node['domain']
			server.certificates = (node/'certificate').map do |cert|
				cert.inner_text
			end
			
			provider.remote.all_waves.each do |wave|
				wave.deltas.each_value do |delta|
					next unless delta.is_a? Sails::Delta
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
			id =~ /^100-(.+)$/
			if $1 && provider[$1]
				wave = provider[$1]
				puts "Got history for #{wave.name}"
				
				(packet/'pubsub/items/item/applied-delta').each do |update|
					delta = Sails::Delta.parse(provider, wave.conv_root_path, Sails::Utils.decode64(update.inner_text), true)
					puts "Got a delta, version #{delta.version}"
				end
				
				wave.apply :newest
			else
				puts "I didn't request this?"
			end
		end
		end
	end
	
	handle 'iq', 'set' do |conn, packet, xml|
		if (xml/'certificate').any?
			node = (xml/'signature').first
			puts "Got a cert from for #{node['domain']}"
			
			server.domain = node['domain']
			server.certificates = (node/'certificate').map do |cert|
				cert.inner_text
			end
			
			provider.remote.all_waves.each do |wave|
				wave.deltas.each_value do |delta|
					next unless delta.is_a? Sails::Delta
					next unless delta.signer_id == server.certificate_hash
					next if delta.server == server
					delta.server = server
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
		
			#when [:message, :normal], [:message, :none]
				#packet.children.each do |message|
					#subtype = message.name
					#if subtype == 'received'
						#if server.state == :details
							#server.state = :ponged
							#puts "#{from} ponged, attempting to send my cert (state = :ponged)"
							#
							#payload = provider.local.certificates64.map do |cert|
								#"<certificate><![CDATA[#{cert}]]></certificate>"
							#end.join ''
							#
							#provider.send_xml 'iq', 'set', from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish node=\"signer\"><item><signature xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" domain=\"#{provider.domain}\" algorithm=\"SHA256\">#{payload}</signature></item></publish></pubsub>"
						#
						#else
							#puts "#{from} ACK'ed our previous packet."
						#end
						#
					#elsif subtype == 'request'
					#
						#if (packet/'event/items/item/wavelet-update').any?
							#wave = nil
							#(packet/'event/items/item/wavelet-update').each do |update|
								#next unless (update/'applied-delta').any?
								#
								#delta = Sails::Delta.parse(provider, update['wavelet-name'], Sails::Utils.decode64(update.inner_text), true)
								#puts "Got delta version #{delta.version rescue -1}"
								#wave = delta.wave if delta
							#end
							#
							#wave.apply(:newest) if wave && wave.complete?(true)
						#end
						#
						#provider.send_xml 'message', 'normal', from, '<received xmlns="urn:xmpp:receipts"/>', id
						#
					#elsif subtype == 'ping'
						#puts "Got a ping from #{from}"
					#
					#end
					#
					#
				#end
				#
			#when [:iq, :error]
				#if (packet/'remote-server-not-found').any?
				#
					#if "wave.#{server.domain}" == server.name
						#puts "Already tried the wave. trick on #{from}. (state = :error)"
						#server.state = :error
					#else
						#puts "Trying the wave. trick on #{from}. (state = :listing)"
						#server.name = "wave.#{server.domain}"
						#server.state = :listing
						#provider.send_xml 'iq', 'get', server.name, '<query xmlns="http://jabber.org/protocol/disco#info"/>'
					#end
					#
				#else
					#puts 'ERROR!'
				#end
				
end # waveserver
end # xmpp
end # sails
