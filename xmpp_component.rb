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
sleep 2

def encode64(data)
	Base64.encode64(data).gsub("\n", '')
end
def decode64(data)
	Base64.decode64(data)
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
			#puts "#{'  '*(tree.size+1)}#{key} => int: #{value}"
		
		elsif type == 2 # Fixed-width (e.g. strings)
			value = {}
			raw = StringIO.new(read_string(data))
			#puts "#{'  '*tree.size}Parsing \##{key}. Tree: #{tree.join(' -> ')} Data: #{raw.string.inspect}"
			
			if (1..8).to_a.map{|num|(2+num*8)}.include?(raw.string[0]) || raw.string[0] == 8
				parse_args value, raw, tree + [key] until raw.eof?
			else
				#puts "#{'  '*tree.size}String: #{raw.string.inspect}"
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

class FakeDelta
	attr_accessor :wave, :version, :hash
	
	def initialize(wave)
		@wave = wave
		@version = 0
		@hash = wave.conv_root_path
	end
end

class Delta
	attr_accessor :applied_to, :wave, :author, :version, :operations
	
	def initialize(wave)
		@applied_to = wave.deltas.last
		@wave = wave
		@author = nil
		@hash = nil
		@version = @applied_to.version + 1
		@operations = []
	end
	
	def self.parse wavelet, data
		data = ProtoBuffer.parse data if data.is_a? String
		
		wavelet =~ /^(.+)\/w\+(.+)\/(.+)$/
		wave_domain, wave_name, wavelet_name = $1, $2, $3
		puts "Parsing #{wave_domain}'s #{wavelet_name} wavelet for w+#{wave_name}"
		
		wave = Wave.find wave_name
		unless wave
			wave = Wave.new wave_domain, wave_name
			Wave.waves << wave
		end
		
		data = data[0].first unless data.size < 4 # remove extra stuff if it's an applied delta
		pp data
		applied_to = data[0].first[0].first[0].first
		version = applied_to + 1
		applied_to = wave.get_delta(applied_to)
		unless applied_to
			applied_to = FakeDelta.new(wave)
			applied_to.version = data[0].first[0].first[0].first
			applied_to.hash = data[0].first[0].first[1].first
		end
		
		return if wave.get_delta(version).is_a? Delta
		
		delta_data = data[0].first
		delta = Delta.new(wave)
		delta.applied_to = applied_to
		delta.version = applied_to.version + 1
		delta.author = delta_data[1].first
		delta.operations = delta_data[2]
		
		wave.deltas << delta
		
		#{0=>
			#[{0=>
				 #[{0=>
						#[{0=>[1],
							#1=>["\340\003\023yt\3001\346\vZ\212\220\a\222_n\371\024= "]}],
					 #1=>["kevin@killerswan.com"],
					 #2=>[{0=>["danopia@danopia.net"]}]}],
				#1=>
				 #[{0=>
						#["Q\206\335\343\215\216D\330u'\020\331\327\325.ex\347y5\023\227\236\r\034\222\202\273\000E\263<\340<\357\2643\266\347y\206\235\256\311\234\026\205{\367\206\327\333 f\305\343M/B\315\215e\216\350G\177P'\333\335\r\360\337\332\354\354\n\026\206\037\335\306\023\303\037N3\205e\210\367_\240\311!U\252]\307\333>\235\207\242\267\202\2532\022\"\260H\227MF\314\005X\377Pp\226\177d\347\035\027}"],
					 #1=>
						#["\e\302\b\236\356\276\316\322Z\325\221e\e\001\357i[\21345\223%}l\322\334\230\234\220\351m\241"],
					 #2=>[1]}]}],
		 #1=>[{0=>[1], 1=>["\340\003\023yt\3001\346\vZ\212\220\a\222_n\371\024= "]}],
		 #2=>[1],
		 #3=>[1256114214507]}
		 delta
	end
	
	def raw
		ProtoBuffer.encode({
			0 => {
				0 => @applied_to.version,
				1 => @applied_to.hash
			},
			1 => @author,
			2 => @operations
		})
	end
	
	def signature
		@@private_key ||= OpenSSL::PKey::RSA.new(File.open("../danopia.net.key").read)
		@@private_key.sign OpenSSL::Digest::SHA1.new, raw
	end
	
	def to_s
		ProtoBuffer.encode({
			0 => {
				0 => raw,
				1 => {
					0 => signature,
					1 => "J\207\315\203\267:Vu\204\216\224\004[.\t(\3670\002\374\3045{7\365\304`qX\030w\305",
					2 => 1 # alg (rsa)
				}
			},
			1 => {
				0 => @applied_to.version, # previous version
				1 => @applied_to.hash # previous hash
			},
			2 => @operations.size, # operations applied
			3 => Time.now.to_i * 1000 # milliseconds not needed yet
		})#[1..-1]
	end
	
	def hash
		@hash = Digest::SHA2.digest("#{@applied_to.hash}#{raw}")[0,20]
	end
	
	def propagate
		
	end
end

class Wave
	attr_accessor :deltas, :host, :name, :participants
	
	def self.waves
		@waves ||= []
	end
	
	def initialize(host, name)
		@host = host
		@name = name
		@participants = []
		
		@deltas = [FakeDelta.new(self)]
	end
	
	def conv_root_path
		"wave://#{host}/w+#{name}/conv+root"
	end
	
	def conv_root_path2
		"#{host}/w+#{name}/conv+root"
	end
	
	def new_delta(author=nil)
		delta = Delta.new self
		delta.author = author
		@deltas << delta
		delta
	end
	
	def self.find(name)
		return nil unless name
		
		@waves ||= []
		waves = @waves.select{|wave| wave.name == name}
		return nil if waves.empty?
		waves.first
	end
	
	def get_delta(version)
		return nil unless version
		
		deltas = @deltas.select{|delta| delta.version == version}
		return nil if deltas.empty?
		deltas.first
	end
	
	def self.add_delta(name, delta)
		wave = find(name)
		wave.deltas << delta
	end
	def self.add_wave(wave)
		@waves << wave
	end
end

wave = Wave.new('danopia.net', 'R0PIDtU751vE')

delta = wave.new_delta "me@danopia.net"
delta.operations << {0 => "me@danopia.net"}

delta = wave.new_delta "me@danopia.net"
delta.operations << {1 => "you@danopia.net"}

#pp delta.raw
#pp delta.signature
#pp delta.to_s

#exit

wave = Wave.new('danopia.net', 'BHW1z9FOWKum')

delta = wave.new_delta 'me@danopia.net'
delta.operations << {0 => 'me@danopia.net'} # Add myself to the conv_root_path
#delta.propagate
#delta.hash

delta = wave.new_delta 'me@danopia.net'
delta.operations << {0 => 'echoe@killerswan.com'} # Add an echoey to the wave
#delta.propagate
#delta.hash

delta = wave.new_delta 'me@danopia.net'
delta.operations << {1 => 'echoe@killerswan.com'}

delta = wave.new_delta 'me@danopia.net'
delta.operations << {0 => 'echoey@killerswan.com'}

Wave.waves << wave

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

#exit

#Parsing "\n\231\001\n\030\b\004\022\024^\257\001l\231IKZ\352\223\346\274\206N\235]\246EWS\022\025echoey@killerswan.com\032f\032d\n\004main\022\\\n\002(\004\n%\032#\n\004line\022\e\n\002by\022\025echoey@killerswan.com\n\002 \001\n+\022)echoey@kshh.us was added to this wavelet.\022\247\001\n\200\001o}\211\237\314t\374\254\034\006\037\v\003\215\361\b\326K\343\254\343\t\304\234\243^\252\257\273\225\310\315q\372\212Y\360\2765\001\237\372\211\325\345@\263\031\005\354\e\\\341\301\021\216\346\351\321\022\333\211K\223\003\372\226\\J\202|\016\373\207R\272\215J\311\330\262\025\a\025\245\377-hg\v\035:\254F'\265\267\023[\240\204\276p\353\305\260\320\355\371@c# \271m`O]&\016L\032\232\344\357\206\205\246\022 \e\302\b\236\356\276\316\322Z\325\221e\e\001\357i[\21345\223%}l\322\334\230\234\220\351m\241\030\001"

#sleep 5

mydomain = 'danopia.net'
myname = "wave.#{mydomain}"

puts "Connecting as #{myname}..."
sock = TCPSocket.new 'localhost', 5275

def sock.send_xml(packet)
	$stdout.puts "Sent: \e[2;34m#{packet}\e[0m" if packet.size > 1
	print packet
end

sock.send_xml '<stream:stream xmlns="jabber:component:accept" xmlns:stream="http://etherx.jabber.org/streams" to="' + myname + '">'

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

sock.send_xml "<handshake>#{key}</handshake>"

message = sock.recv 1024
puts "Recieved: \e[33m#{message}\e[0m"

if message != '<handshake></handshake>'
	puts 'AUTH ERROR!!!'
	exit
end

puts 'Sending ping to killerswan.com'
sock.send_xml '<iq type="get" id="5328-0" to="killerswan.com" from="' + myname + '"><query xmlns="http://jabber.org/protocol/disco#items"/></iq>'

puts 'Setting up keepalive thread'
Thread.new do
	while sleep 60
		sock.send_xml ' '
	end
end

DRb.start_service 'druby://:9000', Wave
trap("INT") { DRb.stop_service }
puts "DRb server running at #{DRb.uri}"

puts 'Entering program loop'

ids = {}
certs = {mydomain => open('../danopia.net.cert').read.split("\n")[1..-2].join('')}
waves = {}

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
		from = packet['from']
		to = packet['to']
		id = packet['id']
		
		case true
		
			# <iq type="get" id="513-92" from="component.danopia.net" to="wave.danopia.net"><query xmlns="http://jabber.org/protocol/disco#info"/></iq>
			when name == 'iq' && type == 'get'
				if (packet/'query').any?
					sock.send_xml '<iq type="result" id="' + id + '" from="' + myname + '" to="' + from + '"><query xmlns="http://jabber.org/protocol/disco#info"><identity category="collaboration" type="google-wave" name="Google Prototype Wave Server - FedOne"/><feature var="http://waveprotocol.org/protocol/0.2/waveserver"/></query></iq>'
					
				# <iq type="get" id="4605-148" from="wave.killerswan.com" to="wave.danopia.net"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="wavelet"><delta-history xmlns="http://waveprotocol.org/protocol/0.2/waveserver" start-version="0" start-version-hash="d2F2ZTovL2Rhbm9waWEubmV0L3crRWx4cG04bWpCN0tJL2NvbnYrcm9vdA==" end-version="3" end-version-hash="RNy5arFR2hAXu+q63y4ESDbWRvE=" wavelet-name="danopia.net/w+Elxpm8mjB7KI/conv+root"/></items></pubsub></iq>
				# start hash: wave://danopia.net/w+Elxpm8mjB7KI/conv+root
				# end hash: gobbledegook
				elsif (packet/'pubsub').any?
					puts "#{from} requested a delta"
					
					wave = Wave.new(mydomain, 'BHW1z9FOWKun')
					
					delta = wave.new_delta "me@#{mydomain}"
					delta.operations << {0 => "me@#{mydomain}"}
					#delta.propagate
					
					delta = wave.new_delta "me@#{mydomain}"
					delta.operations << {0 => "echoey@#{from}"}
					#delta.propagate
					
					waves << wave unless Wave.find_wave('BHW1z9FOWKun')
					
					sock.send_xml '<iq type="result" id="' + id + '" from="' + myname + '" to="' + from + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items><item><applied-delta xmlns="http://waveprotocol.org/protocol/0.2/waveserver"><![CDATA[' + Base64.encode64(wave.deltas[1].to_s).gsub("\n", '') + ']]></applied-delta></item><item><applied-delta xmlns="http://waveprotocol.org/protocol/0.2/waveserver"><![CDATA[' + Base64.encode64(wave.deltas[2].to_s).gsub("\n", '') + ']]></applied-delta></item><item><commit-notice xmlns="http://waveprotocol.org/protocol/0.2/waveserver" version="' + wave.deltas.last.version + '"/></item><item><history-truncated xmlns="http://waveprotocol.org/protocol/0.2/waveserver" version="' + wave.deltas.last.version + '"/></item></items></pubsub></iq>'
					
				end
				
			when name == 'iq' && type == 'set'
				if (packet/'certificate').any?
					puts "Got a cert from #{from}"
					certs[from] = (packet/'certificate').inner_text
					sock.send_xml '<iq type="result" id="' + id + '" from="' + myname + '" to="' + from + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><publish><item node="signer"><signature-response xmlns="http://waveprotocol.org/protocol/0.2/waveserver"/></item></publish></pubsub></iq>'
				
				elsif (packet/'publish').any?
					puts "Publish request from #{from}"
					sock.send_xml '<iq type="result" id="' + id + '" from="' + myname + '" to="' + from + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><publish><item><submit-response xmlns="http://waveprotocol.org/protocol/0.2/waveserver" application-timestamp="1255832011424" operations-applied="1"><hashed-version history-hash="L/WbT5cIaLqt5zvtL1mW/d5Qjl0=" version="5"/></submit-response></item></publish></pubsub></iq>'
				
				end
				
			when name == 'iq' && type == 'result'
				haswave = false
				
				if (packet/'query/item').any?
					puts "Got service listing from #{from}:"
					(packet/'query/item').each do |item|
						puts "\t#{item['name']} (at #{item['jid']})"
						haswave = item['jid'] if item['name'].include? 'Wave Server'
					end
					
					if haswave
						puts "Found wave services on #{from} as #{haswave}, pull details"
						sock.send_xml '<iq type="get" id="3278-1" to="' + haswave + '" from="' + myname + '"><query xmlns="http://jabber.org/protocol/disco#info"/></iq>'
					else
						puts "No wave server found on #{from}"
					end
				
				elsif (packet/'query/identity').any?
					node = (packet/'query/identity').first
					
					if node['type'] == 'google-wave'
						puts "#{from} is a Google Wave service (#{node['name']}). Sending ping."
						sock.send_xml '<message type="normal" to="' + from + '" from="' + myname + '" id="9744-2"><ping xmlns="http://waveprotocol.org/protocol/0.2/waveserver"/><request xmlns="urn:xmpp:receipts"/></message>'
					else
						puts "#{from} is NOT a Google Wave service, it's a \"#{node['name']}\"!"
					end
				
				elsif (packet/'pubsub/publish/item/signature-response').any?
					puts "#{from} responded to cert, now to send a wave. NOT."
					
					wave = Wave.new(mydomain, 'BHW1z9FOWKun')
					
					delta = wave.new_delta "me@#{mydomain}"
					delta.operations << {0 => "me@#{mydomain}"}
					#delta.propagate
					
					delta = wave.new_delta "me@#{mydomain}"
					delta.operations << {0 => "echoey@#{from}"}
					#delta.propagate
					
					#waves << wave unless Wave.find_wave('BHW1z9FOWKun')
					
					#sock.send_xml '<message type="normal" from="' + myname + '" id="4597-8" to="' + from + '"><request xmlns="urn:xmpp:receipts"/><event xmlns="http://jabber.org/protocol/pubsub#event"><items><item><wavelet-update xmlns="http://waveprotocol.org/protocol/0.2/waveserver" wavelet-name="' + wave.conv_root_path2 + '"><applied-delta><![CDATA[' + encode64(wave.deltas[2].to_s) + ']]></applied-delta></wavelet-update></item></items></event></message>'
				end
			
			when name == 'message' && (type == 'normal' || !type)
				subtype = packet.children.first.name
				
				if subtype == 'received'
					if id == '9744-2'
						puts "#{from} ponged, attempting to send the cert and request a delta"
						sock.send_xml '<iq type="set" id="258-4" from="' + myname + '" to="' + from + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><publish node="signer"><item><signature xmlns="http://waveprotocol.org/protocol/0.2/waveserver" domain="' + mydomain + '" algorithm="SHA256"><certificate><![CDATA[' + certs[mydomain] + ']]></certificate></signature></item></publish></pubsub></iq>'
						
						delta = Delta.parse('danopia.net/w+R0PIDtU751vE/conv+root', decode64('CpkBChgIBBIUXq8BbJlJS1rqk+a8hk6dXaZFV1MSFWVjaG9leUBraWxsZXJzd2FuLmNvbRpmGmQKBG1haW4SXAoCKAQKJRojCgRsaW5lEhsKAmJ5EhVlY2hvZXlAa2lsbGVyc3dhbi5jb20KAiABCisSKWVjaG9leUBrc2hoLnVzIHdhcyBhZGRlZCB0byB0aGlzIHdhdmVsZXQuEqcBCoABb32Jn8x0/KwcBh8LA43xCNZL46zjCcSco16qr7uVyM1x+opZ8L41AZ/6idXlQLMZBewbXOHBEY7m6dES24lLkwP6llxKgnwO+4dSuo1KydiyFQcVpf8taGcLHTqsRie1txNboIS+cOvFsNDt+UBjIyC5bWBPXSYOTBqa5O+GhaYSIBvCCJ7uvs7SWtWRZRsB72lbizQ1kyV9bNLcmJyQ6W2hGAE='))
						wave = delta.wave
						sock.send_xml '<iq type="get" id="4605-148" from="' + myname + '" to="' + from + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="wavelet"><delta-history xmlns="http://waveprotocol.org/protocol/0.2/waveserver" start-version="0" start-version-hash="' + encode64(wave.deltas.first.hash) + '" end-version="' + wave.deltas.last.version.to_s + '" end-version-hash="' + encode64(wave.deltas.last.hash) + '" wavelet-name="' + wave.conv_root_path2.sub('/', '!') + '"/></items></pubsub></iq>'
						
					elsif id == '4597-8'
						puts "#{from} ACK'ed the first delta."
						
					else
						puts "#{from} ACK'ed our previous packet."
					end
					
				elsif subtype == 'request'
					(packet/'request/event/items/item/wavelet-update').each do |update|
						delta = Delta.parse(update['wavelet-name'], update.inner_text)
						puts "Got a delta, version #{delta.version}"
					end
					
				end
				
		end
	end
end
