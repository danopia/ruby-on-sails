require 'socket'
require 'digest/sha1'
require 'digest/sha2'

require 'rubygems'
require 'hpricot'

require 'base64'
require 'pp'
require 'openssl'
require 'drb'
require 'yaml'

require 'wave_proto'
require 'wave.danopia.net/lib/sails_remote'

def encode64(data)
	Base64.encode64(data).gsub("\n", '')
end
def decode64(data)
	Base64.decode64(data)
end

puts "Loading config"
config = YAML.load(File.open('sails.conf'))
provider = Provider.new config['domain-name'], config['service-name']

puts "Connecting to #{config['xmpp-connect-host']}:#{config['xmpp-connect-port']} as #{provider.name}..."
sock = TCPSocket.new config['xmpp-connect-host'] || 'localhost', config['xmpp-connect-port'].to_i || 5275
provider.sock = sock

def sock.provider=(provider)
	@provider = provider
end
def sock.ids
	@ids ||= {}
end
def sock.send_raw(packet)
	$stdout.puts "Sent: \e[2;34m#{packet}\e[0m" if packet.size > 1
	print packet
	packet
end
def sock.send_xml(name, type, to, contents, id=nil)
	if type.to_i > 0
		id = type
		type = 'result'
	else
		id ||= "#{(rand*10000).to_i}-#{(rand*100).to_i}"
	end
	
	ids[id] = send_raw("<#{name} type=\"#{type}\" id=\"#{id}\" to=\"#{to}\" from=\"#{@provider.name}\">#{contents}</#{name}>")
	id
end

sock.provider = provider

#################

wave = Wave.new(provider, 'R0PIDtU751vF')

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new("me@#{provider.domain}")
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new("test@#{provider.domain}")
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << MutateOp.new('main', ["(\004",
			{2=>{0=>"line", 1=>{0=>"by", 1=>"me@#{provider.domain}"}}}," \001",
			{1=>"This is a test."}])
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << RemoveUserOp.new("test@#{provider.domain}")
delta.freeze
wave << delta

provider << wave

#################

wave = Wave.new(provider, 'BHW1z9FOWKua')

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new("me@#{provider.domain}") # Add myself to the conv_root_path
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new('echoe@killerswan.com') # Add an echoey to the wave
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << RemoveUserOp.new('echoe@killerswan.com')
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new('echoey@killerswan.com')
delta.freeze
wave << delta

provider << wave

#################

wave = Wave.new(provider, 'ASDFASDFASDF')

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new("me@#{provider.domain}") # Add myself to the conv_root_path
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new('echoe@danopia.net') # Add an echoey to the wave
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << RemoveUserOp.new('echoe@danopia.net')
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new('echoey@danopia.net')
delta.freeze
wave << delta

delta = Delta.new(wave, "me@#{provider.domain}")
delta.operations << AddUserOp.new("danopia@#{provider.domain}")
delta.propagate # !
wave << delta

provider << wave

#p provider['ASDFASDFASDF']
#exit
#################

if config['ping']
	provider << Server.new(provider, config['ping'], config['ping'])
end

sock.send_raw '<stream:stream xmlns="jabber:component:accept" xmlns:stream="http://etherx.jabber.org/streams" to="' + provider.name + '">'

message = sock.recv 1024
puts "Recieved: \e[33m#{message}\e[0m"
doc = Hpricot(message)

id = (doc/'stream:stream').first['id']

unless id
	puts "Unable to connect to XMPP. The server denied the component."
	exit
end

key = Digest::SHA1.hexdigest(id + config['xmpp-password'])

sock.send_raw "<handshake>#{key}</handshake>"

puts 'Setting up keepalive thread'
Thread.new do
	while sleep 60
		sock.send_raw ' '
		#puts 'Sent a space'
	end
end

remote = SailsRemote.serve(provider)
trap("INT") { remote.stop_service; puts 'OBAI'; exit }
puts "DRb server running at #{remote.uri}"

puts 'Entering program loop'

ids = {} # used for history requests
incomplete = ''
until sock.closed?
	message = incomplete + sock.recv(10000)
	puts "Recieved: \e[33m#{message}\e[0m"
	
	if !message || message.empty?
		puts 'Connection closed.'
		exit
	
	elsif message.include? '</stream:stream>'
		puts "Server closed the XMPP component connection."
		remote.stop_service
		exit
	end
	
	doc = Hpricot("<packet>#{message}<done/></packet>")
	
	if (doc/'packet/done').empty? # Didn't get the whole packet
		incomplete = message
		next
	end
	incomplete = ''
	
	doc.root.children.each do |packet|
		name = packet.name
		next if name == 'done'
		
		if name == 'handshake'
			puts "Connected to XMPP."
			provider.state = :ready
			provider.flush
			next
		end
		
		type = packet['type'] || 'none'
		id = packet['id']
		from = packet['from']
		to = packet['to']
		
		case [name.to_sym, type.to_sym]
		
			when [:iq, :get]
				if (packet/'query').any?
					if (packet/'query').first['xmlns'].include?('items')
						sock.send_xml 'iq', id, from, "<query xmlns=\"http://jabber.org/protocol/disco#items\"><item jid=\"#{provider.name}\" name=\"#{config['identity']}\"/></query>"
					else
						sock.send_xml 'iq', id, from, "<query xmlns=\"http://jabber.org/protocol/disco#info\"><identity category=\"collaboration\" type=\"google-wave\" name=\"#{config['identity']}\"/><feature var=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></query>"
					end
					
				elsif (packet/'pubsub').any?
					puts "#{from} requested some deltas"
					
					node = (packet/'pubsub/items/delta-history').first
					node['wavelet-name'] =~ /^(.+)\/w\+(.+)\/(.+)$/
					wave_domain, wave_name, wavelet_name = $1, $2, $3
					wave_domain.sub!('wave://', '')
					
					wave = provider["#{wave_domain}/w+#{wave_name}"]
					payload = ''
					(node['start-version'].to_i..node['end-version'].to_i).each do |version|
						delta = wave[version]
						next unless delta.is_a? Delta
						payload << "<item><applied-delta xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"><![CDATA[#{encode64(delta.to_applied)}]]></applied-delta></item>"
					end
					
					payload << "<item><commit-notice xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" version=\"#{wave[node['end-version'].to_i].version}\"/></item>"
					payload << "<item><history-truncated xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" version=\"#{wave[node['end-version'].to_i].version}\"/></item>"
					
					sock.send_xml 'iq', id, from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items>#{payload}</items></pubsub>"
				end
				
			when [:iq, :set]
				if (packet/'certificate').any?
					puts "Got a cert from #{from}"
					
					server = provider.servers[from.downcase]
					unless server
						server = Server.new(provider, (packet/'signature')['domain'], from.downcase)
						provider << server
					end
					
					server.certificate = (packet/'certificate').inner_text
					
					sock.send_xml 'iq', id, from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish><item node=\"signer\"><signature-response xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></item></publish></pubsub>"
				
				elsif (packet/'publish').any?
					puts "Publish request from #{from} for one of my waves"
					node = (packet/'publish/item/submit-request/delta').first
					delta = Delta.parse(provider, node['wavelet-name'], decode64(node.inner_text))
					
					sock.send_xml 'message', id, from, "<received xmlns=\"urn:xmpp:receipts\"/>"
				end
				
			when [:iq, :result]
				
				if (packet/'query/item').any?
					puts "Got service listing from #{from}:"
					
					haswave = false
					(packet/'query/item').each do |item|
						puts "\t#{item['name']}\t(at #{item['jid']})"
						haswave = item['jid'] if item['name'].include? 'Wave Server'
					end
					
					if haswave
						server = provider.servers[from.downcase]
						if server
							server.name = haswave
							server.state = :listing
						end
						
						puts "Found wave services on #{from} as #{haswave}, pulling details (state = :listing)"
						sock.send_xml 'iq', 'get', haswave, '<query xmlns="http://jabber.org/protocol/disco#info"/>'
					else
						puts "No wave server found on #{from}"
					end
				
				elsif (packet/'query/identity').any?
					node = (packet/'query/identity').first
					
					if node['type'] == 'google-wave'
						server = provider.servers[from.downcase]
						server.state = :details if server
						
						puts "#{from} is Google Wave service (#{node['name']}), sending ping (state = :details)"
						sock.send_xml 'message', 'normal', from, '<ping xmlns="http://waveprotocol.org/protocol/0.2/waveserver"/><request xmlns="urn:xmpp:receipts"/>'
					else
						puts "#{from} is NOT a Google Wave service, it's a \"#{node['name']}\"!"
					end
				
				elsif (packet/'pubsub/publish/item/signature-response').any?
					server = provider.servers[from.downcase]
					if !server
						puts "Unknown server."
					
					elsif server.state == :ponged
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
					
					delta = nil
					(packet/'pubsub/items/item/applied-delta').each do |update|
						delta = Delta.parse(provider, wave.conv_root_path, decode64(update.inner_text), true)
						puts "Got a delta, version #{delta.version}"
					end
					
					wave.apply delta if delta # apply the latest only for less output
				end
			
			when [:message, :normal], [:message, :none]
				packet.children.each do |message|
					subtype = message.name
					if subtype == 'received'
						server = provider.servers[from.downcase]
						if !server
							puts "Unknown server."
						
						elsif server.state == :details
							server.state = :ponged
							puts "#{from} ponged, attempting to send my cert (state = :ponged)"
							
							sock.send_xml 'iq', 'set', from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish node=\"signer\"><item><signature xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" domain=\"#{provider.domain}\" algorithm=\"SHA256\"><certificate><![CDATA[#{provider.certificate}]]></certificate></signature></item></publish></pubsub>"
						
						else
							puts "#{from} ACK'ed our previous packet."
						end
						
					elsif subtype == 'request'
					
						if (packet/'event/items/item/wavelet-update').any?
							wave = nil
							(packet/'event/items/item/wavelet-update').each do |update|
								delta = Delta.parse(provider, update['wavelet-name'], decode64(update.inner_text), true)
								puts "Got delta version #{delta.version}"
								wave = delta.wave
							end
							
							wave.apply(wave.newest) if wave.complete?(ids)
						end
						
						sock.send_xml 'message', 'normal', from, '<received xmlns="urn:xmpp:receipts"/>', id
						
					elsif subtype == 'ping'
						puts "Got a ping from #{from}"
					
					end
					
					
				end
			
			else
				puts "Unknown packet"
				
		end
	end
end
