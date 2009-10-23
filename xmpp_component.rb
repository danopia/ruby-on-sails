require 'socket'
require 'digest/sha1'
require 'digest/sha2'

require 'rubygems'
require 'hpricot'

require 'stringio'
require 'base64'
require 'pp'
require 'openssl'
require 'drb'

require 'wave.danopia.net/lib/sails_remote.rb'

sleep 2

def encode64(data)
	Base64.encode64(data).gsub("\n", '')
end
def decode64(data)
	Base64.decode64(data)
end

class Provider
	attr_accessor :certs, :cert_hash, :domain, :name, :waves
	
	def initialize(domain, subdomain='wave')
		@certs = {}
		@cert_hash = nil
		@domain = domain
		@name = "#{subdomain}.#{domain}"
		@waves = {}
		
		@certs[domain] = open("#{domain}.cert").read.split("\n")[1..-2].join('')
	end
	
	def cert_hash
		return @cert_hash if @cert_hash
		@cert_hash = decode64(@certs[@domain])
		@cert_hash = Digest::SHA2.digest "0\202\003\254#{@cert_hash}"
	end
	
	def [](name)
		return @waves[name] if @waves.has_key?(name)
		
		# allow fallback to not specifing a domain
		waves = @waves.values.select{|wave|wave.name == name}
		return nil if waves.empty?
		waves.first
	end
	
	def <<(wave)
		@waves[wave.path] = wave
	end
end

class ProtoBuffer
	def self.parse(data)
		data = StringIO.new(data)
		
		puts "Parsing #{data.string.inspect}"
		
		hash = {}
		parse_args hash, data, [] until data.eof?
		
		#puts "Done."
		#pp hash
		
		hash
	end
	
	def self.parse_args(parent_args, data, tree)
		key = data.getc
		type = key % 8
		key = (key / 8) - 1
		
		value = -1
		
		if type == 0 # Varint
			value = read_varint(data)
			puts "#{'  '*(tree.size)}#{key} => int: #{value}"
		
		elsif type == 2 # Fixed-width (e.g. strings)
			value = {}
			raw = StringIO.new(read_string(data))
	
			if (1..8).to_a.map{|num|(2+num*8)}.include?(raw.string[0]) || raw.string[0] == 8 || tree == [0, 2, 2, 1]
				puts "#{'  '*tree.size}parsing \##{key}. Tree: #{tree.join(' -> ')} Data: #{raw.string.inspect}"
				parse_args value, raw, tree + [key] until raw.eof?
			else
				puts "#{'  '*tree.size}#{key} => string: #{raw.string.inspect}"
				value = raw.string
			end
		
		else
			puts "Unknown type: #{type}"
		end
		
		parent_args[key] ||= []
		parent_args[key] << value
	end
	
	def self.read_varint(io)
		index = 0
		value = 0
		while true
			byte = io.getc
			if byte & 0x80 > 0
				value |= (byte & 0x7F) << index
				index += 7
			else
				return value | byte << index
			end
		end
	end
	def self.read_string(io)
		io.read read_varint(io)
	end

	def self.write_varint(value)
		bytes = ''
		while value > 0x7F
			bytes << ((value & 0x7F) | 0x80).chr
			value >>= 7
		end
		bytes << value.chr
	end
	def self.write_string(io, string)
		io << write_varint(string.size) << string
	end
	
	def self.encode(hash)
		output = ''
		hash.each_pair do |type, value|
			value = [value] unless value.is_a? Array
			value.each do |arg|
				if arg.is_a? Hash
					output << (type*8+10).chr
					write_string output, encode(arg)
				elsif arg.is_a?(Fixnum) || arg.is_a?(Bignum)
					output << (type*8+8).chr
					output << write_varint(arg)
				else
					output << (type*8+10).chr
					write_string output, arg
				end
			end
		end
		output
	end
end

provider = Provider.new 'danopia.net'

#pp Delta.parse(provider, 'danopia.net/w+R0PIDtU751vE/conv+root', decode64('CpkBChgIBBIUXq8BbJlJS1rqk+a8hk6dXaZFV1MSFWVjaG9leUBraWxsZXJzd2FuLmNvbRpmGmQKBG1haW4SXAoCKAQKJRojCgRsaW5lEhsKAmJ5EhVlY2hvZXlAa2lsbGVyc3dhbi5jb20KAiABCisSKW1lQGRhbm9waWEubmV0IHdhcyBhZGRlZCB0byB0aGlzIHdhdmVsZXQuEqcBCoABaC9kcKxqj+QpKRrBJTXHSI+uVc4dhCNJfPSXhsm+gxVeJEr1STurX7WW6DWFAk5MXzdGNVqgLgY8mdf1OYnzl+M+yfDVP0O1U033jyMp+f1z8gaHM+8eFnp701ergWiseUmSXCgwAgpIefDWTnJM6RMLd4LbPHh4wV2j7zzxA5MSIBvCCJ7uvs7SWtWRZRsB72lbizQ1kyV9bNLcmJyQ6W2hGAE='))
#exit

#################

wave = Wave.new(provider, 'R0PIDtU751vF')

delta = Delta.new(wave, "me@danopia.net")
delta.operations << AddUserOp.new("me@danopia.net")
wave << delta

delta = Delta.new(wave, "me@danopia.net")
delta.operations << AddUserOp.new("test@danopia.net")
wave << delta

delta = Delta.new(wave, "me@danopia.net")
delta.operations << MutateOp.new('main', "This is a test.")
#{2=>{2=>{0=>"main",1=> {0=>["(\004",
#	{2=>{0=>"line", 1=>{0=>"by", 1=>author}}}," \001",
#	{1=>text}]}}}}
wave << delta

delta = Delta.new(wave, "me@danopia.net")
delta.operations << RemoveUserOp.new("test@danopia.net")
wave << delta

provider << wave

#################

wave = Wave.new(provider, 'BHW1z9FOWKua')

delta = Delta.new(wave, "me@danopia.net")
delta.operations << AddUserOp.new('me@danopia.net') # Add myself to the conv_root_path
wave << delta

delta = Delta.new(wave, "me@danopia.net")
delta.operations << AddUserOp.new('echoe@killerswan.com') # Add an echoey to the wave
wave << delta

delta = Delta.new(wave, "me@danopia.net")
delta.operations << RemoveUserOp.new('echoe@killerswan.com')
wave << delta

delta = Delta.new(wave, "me@danopia.net")
delta.operations << AddUserOp.new('echoey@killerswan.com')
wave << delta

provider << wave

#################

#pp wave.deltas
#pp Delta.parse('killerswan.com/w+l5PdmqP1fk7y/conv+root', decode64('CuMCCrYBChgIBRIUQMqHNhGIufPL+x6p4yduyHwjOqESFGtldmluQGtpbGxlcnN3YW4uY29tGoMBGoABCgRtYWluEngKAihRCiQaIgoEbGluZRIaCgJieRIUa2V2aW5Aa2lsbGVyc3dhbi5jb20KAiABCkgSRmkgZG9uJ3Qgc2VlIHRoZSBkaWZmZXJlbmNlIGJldHdlZW4gbWluZSBhbmQgeW91cnMsIGJ1dCBoZWxsLCB3aG8ga25vd3MSpwEKgAEd99hVpTJdkEO2GGOLBpPVw11V9PEuInlk7hAlrK9KdYziQ4n9K24Om2DQ17fufpIcgM+PUpwd3Ky2qMe7CrpsEEye9B/Gy9m7hqnqH31fBz1ZenkGYoGH+3lC3t/GPq9lnsrhhc78/QDYkR1lPrxGgQ1H1yc+Pl1guzMLdIEosxIgG8IInu6+ztJa1ZFlGwHvaVuLNDWTJX1s0tyYnJDpbaEYARIYCAUSFEDKhzYRiLnzy/seqeMnbsh8IzqhGAEgmJb7scck'))
#exit

#\n\231\001
#	\n\030
#		\b\004 # applied to version
#		\022\024^\257\001l\231IKZ\352\223\346\274\206N\235]\246EWS # applied to hash
#	\022\025 echoey@killerswan.com # author
#	\032f # operation
#		\032d # mutate doc
#			\n\004 main # doc id
#			\022\\ # doc operation
#				\n\002 (\004 # retain item count = 4
#				\n%\032# # element
#					\n\004 line # type
#					\022\e # attribute
#						\n\002 by # key
#						\022\025 echoey@killerswan.com # value
#			\n\002 \001 # element end
#			\n+
#				\022) echoey@kshh.us was added to this wavelet. # charactors
#\022\247\001
#	\n\200\001 o}\211\237\314t\374\254\034\006\037\v\003\215\361\b\326K\343\254\343\t\304\234\243^\252\257\273\225\310\315q\372\212Y\360\2765\001\237\372\211\325\345@\263\031\005\354\e\\\341\301\021\216\346\351\321\022\333\211K\223\003\372\226\\J\202|\016\373\207R\272\215J\311\330\262\025\a\025\245\377-hg\v\035:\254F'\265\267\023[\240\204\276p\353\305\260\320\355\371@c# \271m`O]&\016L\032\232\344\357\206\205\246
#	\022  \e\302\b\236\356\276\316\322Z\325\221e\e\001\357i[\21345\223%}l\322\334\230\234\220\351m\241
#	\030\001

#delta = Delta.parse('danopia.net/w+R0PIDtU751vE/conv+root', decode64('CpkBChgIBBIUXq8BbJlJS1rqk+a8hk6dXaZFV1MSFWVjaG9leUBraWxsZXJzd2FuLmNvbRpmGmQKBG1haW4SXAoCKAQKJRojCgRsaW5lEhsKAmJ5EhVlY2hvZXlAa2lsbGVyc3dhbi5jb20KAiABCisSKWVjaG9leUBrc2hoLnVzIHdhcyBhZGRlZCB0byB0aGlzIHdhdmVsZXQuEqcBCoABb32Jn8x0/KwcBh8LA43xCNZL46zjCcSco16qr7uVyM1x+opZ8L41AZ/6idXlQLMZBewbXOHBEY7m6dES24lLkwP6llxKgnwO+4dSuo1KydiyFQcVpf8taGcLHTqsRie1txNboIS+cOvFsNDt+UBjIyC5bWBPXSYOTBqa5O+GhaYSIBvCCJ7uvs7SWtWRZRsB72lbizQ1kyV9bNLcmJyQ6W2hGAE='))

#wave = delta.wave

#puts '<iq type="get" id="4605-148" from="' + 'wave.danopia.net' + '" to="' + 'asdf' + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="wavelet"><delta-history xmlns="http://waveprotocol.org/protocol/0.2/waveserver" start-version="0" start-version-hash="' + encode64(wave.deltas.first.hash) + '" end-version="' + wave.deltas.last.version.to_s + '" end-version-hash="' + encode64(wave.deltas.last.hash) + '" wavelet-name="danopia.net!w+R0PIDtU751vE/conv+root"/></items></pubsub></iq>'

puts "Connecting as #{provider.name}..."
sock = TCPSocket.new 'localhost', 5275

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
end

sock.provider = provider

sock.send_raw '<stream:stream xmlns="jabber:component:accept" xmlns:stream="http://etherx.jabber.org/streams" to="' + provider.name + '">'

message = sock.recv 1024
puts "Recieved: \e[33m#{message}\e[0m"
doc = Hpricot(message)

id = (doc/'stream:stream').first['id']

unless id
	puts "Unable to connect to XMPP. The server denied the component."
	exit
end

key = Digest::SHA1.hexdigest(id + 'yaywave')

puts "Got stream ID #{id}, using #{key} to handshake"

sock.send_raw "<handshake>#{key}</handshake>"

message = sock.recv 1024
puts "Recieved: \e[33m#{message}\e[0m"

if message != '<handshake></handshake>'
	puts 'AUTH ERROR!!!'
	exit
end

puts 'Sending ping to killerswan.com'
sock.send_xml 'iq', 'get', 'killerswan.com', '<query xmlns="http://jabber.org/protocol/disco#items"/>'

puts 'Setting up keepalive thread'
Thread.new do
	while sleep 60
		sock.send_xml ' '
	end
end

remote = SailsRemote.serve(provider)
trap("INT") { remote.stop_service }
puts "DRb server running at #{remote.uri}"

puts 'Entering program loop'

until sock.closed?
	message = sock.recv 10000
	if !message || message.empty?
		puts 'Connection closed.'
		exit
	end
	
	puts "Recieved: \e[33m#{message}\e[0m"
	doc = Hpricot("<packet>#{message}</packet>")
	
	doc.root.children.each do |packet|
		name = packet.name
		type = packet['type']
		id = packet['id']
		from = packet['from']
		to = packet['to']
		
		case [name.to_sym, type.to_sym]
		
			when [:iq, :get]
				if (packet/'query').any?
					sock.send_xml 'iq', id, from, '<query xmlns="http://jabber.org/protocol/disco#info"><identity category="collaboration" type="google-wave" name="Google Prototype Wave Server - FedOne"/><feature var="http://waveprotocol.org/protocol/0.2/waveserver"/></query>'
					
				# <pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="wavelet"><delta-history xmlns="http://waveprotocol.org/protocol/0.2/waveserver" start-version="0" start-version-hash="d2F2ZTovL2Rhbm9waWEubmV0L3crRWx4cG04bWpCN0tJL2NvbnYrcm9vdA==" end-version="3" end-version-hash="RNy5arFR2hAXu+q63y4ESDbWRvE=" wavelet-name="danopia.net/w+Elxpm8mjB7KI/conv+root"/></items></pubsub>
				elsif (packet/'pubsub').any?
					puts "#{from} requested some deltas"
					
					node = (packet/'pubsub/items/delta-history/')
					node['wavelet-name'] =~ /^(.+)\/w\+(.+)\/(.+)$/
					wave_domain, wave_name, wavelet_name = $1, $2, $3
					
					wave = provider["#{wave_domain}/w+#{wave_name}"]
					payload = ''
					(node['start-version'].to_i..node['end-version'].to_i).each do |version|
						delta = wave[version]
						payload << "<item><applied-delta xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"><![CDATA[#{encode64(delta.to_s)}]]></applied-delta></item>"
					end
					
					payload << "<item><commit-notice xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" version=\"#{wave[node['end-version'].to_i].version}\"/></item>"
					payload << "<item><history-truncated xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" \"#{wave[node['end-version'].to_i].version}\"/></item>"
					
					sock.send_xml 'iq', id, from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><items>#{payload}</items></pubsub>"
					
				end
				
			when [:iq, :set]
				if (packet/'certificate').any?
					puts "Got a cert from #{from}"
					provider.certs[from] = (packet/'certificate').inner_text
					sock.send_xml 'iq', id, from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish><item node=\"signer\"><signature-response xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\"/></item></publish></pubsub>"
				
				elsif (packet/'publish').any?
					puts "Publish request from #{from}"
					sock.send_xml 'iq', id, from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish><item><submit-response xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" application-timestamp=\"1255832011424\" operations-applied=\"1\"><hashed-version history-hash=\"L/WbT5cIaLqt5zvtL1mW/d5Qjl0=\" version=\"5\"/></submit-response></item></publish></pubsub>"
				
				end
				
			when [:iq, :result]
				
				if (packet/'query/item').any?
					puts "Got service listing from #{from}:"
					
					haswave = false
					(packet/'query/item').each do |item|
						puts "\t#{item['name']} (at #{item['jid']})"
						haswave = item['jid'] if item['name'].include? 'Wave Server'
					end
					
					if haswave
						puts "Found wave services on #{from} as #{haswave}, pulling details"
						sock.send_xml 'iq', 'get', haswave, '<query xmlns="http://jabber.org/protocol/disco#info"/>'
					else
						puts "No wave server found on #{from}"
					end
				
				elsif (packet/'query/identity').any?
					node = (packet/'query/identity').first
					
					if node['type'] == 'google-wave'
						puts "#{from} is Google Wave service (#{node['name']}). Sending ping."
						sock.send_xml 'message', 'normal', from, '<ping xmlns="http://waveprotocol.org/protocol/0.2/waveserver"/><request xmlns="urn:xmpp:receipts"/>', '9744-2'
					else
						puts "#{from} is NOT a Google Wave service, it's a \"#{node['name']}\"!"
					end
				
				elsif (packet/'pubsub/publish/item/signature-response').any?
					puts "#{from} responded to cert, now to send wave BHW1z9FOWKua."
					
					wave = provider['BHW1z9FOWKua']
					
					sock.send_xml 'message', 'normal', from, "<request xmlns=\"urn:xmpp:receipts\"/><event xmlns=\"http://jabber.org/protocol/pubsub#event\"><items><item><wavelet-update xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" wavelet-name=\"#{wave.conv_root_path.sub('/', '!')}\"><applied-delta><![CDATA[#{encode64(wave.newest.to_s)}]]></applied-delta></wavelet-update></item></items></event>"
				end
			
			when [:message, :normal]
				subtype = packet.children.first.name
				
				if subtype == 'received'
					if id == '9744-2'
						puts "#{from} ponged, attempting to send the cert and request a delta"
						sock.send_xml 'iq', 'set', from, "<pubsub xmlns=\"http://jabber.org/protocol/pubsub\"><publish node=\"signer\"><item><signature xmlns=\"http://waveprotocol.org/protocol/0.2/waveserver\" domain=\"#{provider.domain}\" algorithm=\"SHA256\"><certificate><![CDATA[#{provider.certs[provider.domain]}]]></certificate></signature></item></publish></pubsub>"
						
						#sock.send_xml '<iq type="get" id="4605-148" from="' + myname + '" to="' + from + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="wavelet"><delta-history xmlns="http://waveprotocol.org/protocol/0.2/waveserver" start-version="0" start-version-hash="' + encode64(wave.deltas.first.hash) + '" end-version="' + wave.deltas.last.version.to_s + '" end-version-hash="' + encode64(wave.deltas.last.hash) + '" wavelet-name="' + wave.conv_root_path.sub('/', '!') + '"/></items></pubsub></iq>'
						
					else
						puts "#{from} ACK'ed our previous packet."
					end
					
				elsif subtype == 'request'
					(packet/'request/event/items/item/wavelet-update').each do |update|
						delta = Delta.parse(update['wavelet-name'], update.inner_text)
						puts "Got a delta, version #{delta.version}"
					end
					
				end
			
			else
				puts "Unknown packet"
				
		end
	end
end
