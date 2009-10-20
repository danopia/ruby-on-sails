require 'socket'
require 'digest/sha1'
require 'digest/sha2'

require 'rubygems'
require 'hpricot'

require 'socket'
require 'stringio'
require 'base64'
sleep 2

  #delta: "\n\030\b\003\022\024\326\002\021j\213\334J\256\253G;^\270\274\022\274\003Gq\307\022\023danopia@danopia.net\032D\032B\n\004main\022:\n\002(\004\n#\032!\n\004line\022\031\n\002by\022\023danopia@danopia.net\n\002 \001\n\v\022\twhat\'s up"
  #signature {
    #signature_bytes: "\030\006\364\331\352\355tn\266\206\301\353m\247\020lb2n:T.\227\325\366%,s\312\355t\f<C\003C;\303\212|\031\"\024\261\2779\363\366(WF!\"\370\353\0353\301\240\233\2346\206\261\361\017H\356\235\017Z@\242\340\277\232OYD?\020q\tT\020\001Ec\361\003\352j\332\276\252p6c\273^9\232/\273I4y8:\372\343!r;\232EMK\323\330D\207\000c\2778O"
    #signer_id: "J\207\315\203\267:Vu\204\216\224\004[.\t(\3670\002\374\3045{7\365\304`qX\030w\305"
    #signature_algorithm: SHA1_RSA
  #}
#}
#hashed_version_applied_at {
  #version: 3
  #history_hash: "\326\002\021j\213\334J\256\253G;^\270\274\022\274\003Gq\307"
#}
#operations_applied: 1
#application_timestamp: 1255981572223

require 'openssl'

def sign_delta(data)
	@@private_key ||= OpenSSL::PKey::RSA.new(File.open("../danopia.net.key").read)
	@@private_key.sign(OpenSSL::Digest::SHA1.new, data)
end

def hash_delta(previous_hash, delta)
	Digest::SHA2.digest("#{previous_hash}#{delta}")[0,20]
end

class ProtoBuffer
	def self.parse(data)
		data = StringIO.new(data)
		
		puts "Parsing #{data.string.inspect}"
		
		hash = {}
		until data.eof?
			parse_args hash, data, []
		end
		
		puts "Done."
		p hash
		
		hash
	end
	
	def self.parse_args(parent_args, data, tree)
		puts "Reading a byte."
		key = (data.getc-10).to_f/8
		if key == -2
			puts "RETURNED"
			return
		end
		
		if key == -0.25 || key == 1.75 || key == 2.75 #|| (tree.size == 3 && tree[2] == 0 && key == 1)
			key = 0 if key == -0.25
			key = 2 if key == 1.75
			key = 3 if key == 2.75
			#data.getc if raw.string[0] == 8
			value = read_varint(data)
			puts ('  '*tree.size) + "#{key} => int: #{value}"
			parent_args[key] ||= []
			parent_args[key] << value
			return
		end
		key = key.to_i
		
		args = {}
		puts ('  '*tree.size) + "Reading \##{key}. Tree: #{tree.join(' -> ')} BYTES: #{data.string.size - data.pos}"
		raw = StringIO.new(read_string(data))
		puts ('  '*tree.size) + "Parsing \##{key}. Tree: #{tree.join(' -> ')} Data: #{raw.string.inspect}"
		
		if !(1..8).to_a.map{|num|(2+num*8)}.include?(raw.string[0]) && raw.string[0] != 8
			puts ('  '*tree.size) + "String: #{raw.string.inspect}"
			parent_args[key] ||= []
			parent_args[key] << raw.string
			return
		end
		
		tree << key
		until raw.eof?
			parse_args args, raw, tree
		end
		tree.pop
		
		parent_args[key] ||= []
		parent_args[key] << args
	end
	
	def self.read_varint(io)
		puts "Reading a varint..."
		index = 0
		value = 0
		while true
			byte = io.getc
			if byte & 0x80 > 0
				value |= (byte & 0x7F) << index
				index += 7
			else
				value |= byte << index
				#io.ungetc byte
				puts "Read #{index/7+1} bytes."
				return value
			end
		end
	end
	def self.read_string(io)
		size = read_varint(io)
		p size
		io.read size
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
				elsif arg.is_a? Fixnum
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

#	\n\355\001 - arg 0 (length 237)
#		\nA - arg 0 (length 65)
# 		\n\030 - arg 0 (length 24)
#				\b\003 - arg 0 (varint) - 3
#					\022\024 - arg 1 (string) - D\334\271j\261Q\332\020\027\273\352\272\337.\004H6\326F\361
#			\022\023 - arg 1 (string) - danopia@danopia.net
#			\032\020 - arg 2 (length 16)
#				\n\016 - arg 0 (string) - echoey@kshh.us
#	\022\247\001 - arg 1 (length 167)
#		\n\200\001 - arg 0 (length 128)
#			\022\241Xr\307\365\335\310\310 \304\354\250\241\a\237\030\262v\031\250>\024\016\234\336U\020t\027\326\312\031\374\233\362\366\204\225{\211\005e\246SS\204;\244I\333\233\263o\320\223\032\034\221\351Z\357\233Ih\032\e\316\002LX\237F)Z\223oT\000\345\244\253\177\307LD\213~\305\t\031\337\375\335\372#\242\031\330D\240i@\001\325\307\311\307m\364\326^\257\224`U\324J\351W\326\356\323\316\265\211\240Q\"\004\250|\330;s\245gXH\351@E\262\340\222\217s\000/\314CW\263\177\\F\a\025\201\207|Q\200\021

#!\200\2001!DM\313\226\253\025\035\241\001{\276\253\255\362\340D\203mdo\021\200\022\t\372\272\352\274b@

data = "\n\355\001\nA\n\030\b\003\022\024D\334\271j\261Q\332\020\027\273\352\272\337.\004H6\326F\361\022\023danopia@danopia.net\032\020\n\016echoey@kshh.us\022\247\001\n\200\001\022\241Xr\307\365\335\310\310 \304\354\250\241\a\237\030\262v\031\250>\024\016\234\336U\020t\027\326\312\031\374\233\362\366\204\225{\211\005e\246SS\204;\244I\333\233\263o\320\223\032\034\221\351Z\357\233Ih\032\e\316\002LX\237F)Z\223oT\000\345\244\253\177\307LD\213~\305\t\031\337\375\335\372#\242\031\330D\240i@\001\325\307\311\307m\364\326^\257\224`U\324J\351W\326\356\323\316\265\211\240Q\"\004\250|\330;s\245gXH\351@E\262\340\222\217s\000/\314CW\263\177\\F\a\025\201\207|Q\200\021!\200\2001!DM\313\226\253\025\035\241\001{\276\253\255\362\340D\203mdo\021\200\022\t\372\272\352\274b@" # Initial

data = "\n\357\001\nC\n\030\b\001\022\024\361\207{\331\357\370~\276\206\243\016$\207\234m\v!bH-\022\023danopia@danopia.net\032\022\n\020meep@danopia.net\022\247\001\n\200\001\203\370\231g\246Rt\276\355\372\003\324\321p\311\261\337\2510(fSH\005I1V\222\360\357gNMD\211\334\003\330VKf\242K\264\247\373\002\357\t\200,mm\234\350\037*F\001V\271$\236\375\343\2168\372\205\027G\017\362\344\275zL\372\271\253\320\2420\244\227\342#\355\263+\257\216\273\324\353\252\021\326\376>\235\327\325\257\374I\255\036\335\275-#\227|\246\002A\336\337\017%Q\aO~\004\t\001\"\004\250|\330;s\245gXH\351@E\262\340\222\217s\000/\314CW\263\177\\F\a\025\201\207|Q\200\021!\200\200\021!O\030w\275\236\377\207\353\350j0\342Hy\306\320\262\026$\202\321\200\022\n>J\252\274b@" # Second of the second packet

data = "\n\362\001\nF\n\030\b\001\022\024\242\220\231\340\315Z\252wF\247\245H\363\303\352\377\347\306\254;\022\023danopia@danopia.net\032\025\n\023echoey@acmewave.com\022\247\001\n\200\001&\026\001#\345\352\313\262\215\247\005\311K$\2027\bSP\231\303\275\357\235_CC\371\301\274\316\b/\345\350_\346\231\315e\237*iO^\233\307\205\252\336\220\354\362\251\376\325{\277aqq\332\253\n\031\271\333W\222\310\273r\277\354I}\347\303\346\030*$S\215\344b\226\342x\327\224\333\204\e`\337{(\345\211\215&0A;\376D\030\355|\016\253\233\311\250\024\006>\216\317\375\365YI\252\214\250\241\"\004\250|\330;s\245gXH\351@E\262\340\222\217s\000/\314CW\263\177\\F\a\025\201\207|Q\200\021!\200\200\021!J)\t\236\f\325\252\247tjzT\217<>\257\376|j\303\261\200\022\b\274o\277,b@"

p ProtoBuffer.encode({
	0 => {
		0 => 0,
		1 => 'wave://danopia.net/w+BHW1z9FOWKum/conv+root'
	},
	1 => 'me@danopia.net',
	2 => {
		0 => 'me@danopia.net'
	}
})
delta = "\n/\b\000\022+wave://danopia.net/w+BHW1z9FOWKum/conv+root\022\016me@danopia.net\032\020\n\016me@danopia.net"
p delta
signature = sign_delta(delta)
p signature

data = "\n\377\001\nS#{delta}\022\247\001\n\200\001#{signature}\022 J\207\315\203\267:Vu\204\216\224\004[.\t(\3670\002\374\3045{7\365\304`qX\030w\305\030\001\022/\b\000\022+wave://danopia.net/w+BHW1z9FOWKum/conv+root\030\001 \364\302\274\237\307$"

puts Base64.encode64(hash_delta('wave://danopia.net/w+BHW1z9FOWKum/conv+root', data))
hash = ProtoBuffer.parse data
#p hash
exit

#doc = Hpricot('<packet><iq type="get" id="513-92" from="component.danopia.net" to="wave.danopia.net"><query xmlns="http://jabber.org/protocol/disco#info"/></iq><iq type="get" id="513-92" from="component.danopia.net" to="wave.danopia.net"><query xmlns="http://jabber.org/protocol/disco#info"/></iq></packet>')

#p doc.root.children.first.name
#exit

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

puts 'Sending ping to kshh.us'
sock.send_xml '<iq type="get" id="5328-0" to="r-o-o-t.net" from="' + myname + '"><query xmlns="http://jabber.org/protocol/disco#items"/></iq>'

puts 'Setting up keepalive thread'
Thread.new do
	while sleep 60
		sock.send_xml ' '
	end
end

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
					
				# <iq type="get" id="4605-148" from="wave.kshh.us" to="wave.danopia.net"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="wavelet"><delta-history xmlns="http://waveprotocol.org/protocol/0.2/waveserver" start-version="0" start-version-hash="d2F2ZTovL2Rhbm9waWEubmV0L3crRWx4cG04bWpCN0tJL2NvbnYrcm9vdA==" end-version="3" end-version-hash="RNy5arFR2hAXu+q63y4ESDbWRvE=" wavelet-name="danopia.net/w+Elxpm8mjB7KI/conv+root"/></items></pubsub></iq>
				elsif (packet/'pubsub').any?
					puts "#{from} requested a delta"
					sock.send_xml '<iq type="result" id="' + id + '" from="' + myname + '" to="' + from + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items><item><applied-delta xmlns="http://waveprotocol.org/protocol/0.2/waveserver"><![CDATA[CokCCl0KLwgAEit3YXZlOi8vZGFub3BpYS5uZXQvdytFbHhwbThtakI3S0kvY29udityb290EhNkYW5vcGlhQGRhbm9waWEubmV0GhUKE2Rhbm9waWFAZGFub3BpYS5uZXQSpwEKgAGz82n9YVZnwleA9O8EeAa7kls02MnZR5+VzQpZAUAwXZntnLuXCBHxHru7Z9KqHCzy9bPvG+3tuoJcrujwFgRgacW4XVNF0z+dOxWaxJaJT9hTzkiZ9d8tuogW77HxhLZwFa2AwKZV0MvPmUgnkKBlqLJnuivr1zDk7tjqUMydLhIgSofNg7c6VnWEjpQEWy4JKPcwAvzENXs39cRgcVgYd8UYARIvCAASK3dhdmU6Ly9kYW5vcGlhLm5ldC93K0VseHBtOG1qQjdLSS9jb252K3Jvb3QYASC9iKqrxiQ=]]></applied-delta></item><item><applied-delta xmlns="http://waveprotocol.org/protocol/0.2/waveserver"><![CDATA[Cu8BCkMKGAgBEhTxh3vZ7/h+voajDiSHnG0LIWJILRITZGFub3BpYUBkYW5vcGlhLm5ldBoSChBtZWVwQGRhbm9waWEubmV0EqcBCoABg/iZZ6ZSdL7t+gPU0XDJsd+pMChmU0gFSTFWkvDvZ05NRIncA9hWS2aiS7Sn+wLvCYAsbW2c6B8qRgFWuSSe/eOOOPqFF0cP8uS9ekz6uavQojCkl+Ij7bMrr46LvU66oR1v4+ndfVr/xJrR7dvS0jl3ymAkHe3w8lUQdPfgQJASIEqHzYO3OlZ1hI6UBFsuCSj3MAL8xDV7N/XEYHFYGHfFGAESGAgBEhTxh3vZ7/h+voajDiSHnG0LIWJILRgBIKPkqqvGJA==]]></applied-delta></item><item><applied-delta xmlns="http://waveprotocol.org/protocol/0.2/waveserver"><![CDATA[CpYCCmoKGAgCEhSlskJ2QEVDSeR/hN+QsPVnN9T0kRITZGFub3BpYUBkYW5vcGlhLm5ldBo5GjcKBG1haW4SLwojGiEKBGxpbmUSGQoCYnkSE2Rhbm9waWFAZGFub3BpYS5uZXQKAiABCgQSAmhpEqcBCoABoO2816jli/LHg6KJayGTV1ifIniLQDqSzoMHuVaZEQAAmqT6jR830qPYec3jK2eMuKepFkucig4UyuOsY2zkErZD/opKJhi44cOcEA+GY3arpp9JwgM+Y99M55+dD+fT2dupgBMEUrESZP0mx3QMGUnbAJ5/+vnSZcDzn1NQRgYSIEqHzYO3OlZ1hI6UBFsuCSj3MAL8xDV7N/XEYHFYGHfFGAESGAgCEhSlskJ2QEVDSeR/hN+QsPVnN9T0kRgBIIr1qqvGJA==]]></applied-delta></item><item><commit-notice xmlns="http://waveprotocol.org/protocol/0.2/waveserver" version="3"/></item><item><history-truncated xmlns="http://waveprotocol.org/protocol/0.2/waveserver" version="3"/></item></items></pubsub></iq>'
					
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
					puts "#{from} responded to cert, now to send a wave."
					sock.send_xml '<message type="normal" from="' + myname + '" id="4597-8" to="' + from + '"><request xmlns="urn:xmpp:receipts"/><event xmlns="http://jabber.org/protocol/pubsub#event"><items><item><wavelet-update xmlns="http://waveprotocol.org/protocol/0.2/waveserver" wavelet-name="' + mydomain + '/w+Elxpm8mjB7KI/conv+root"><applied-delta><![CDATA[Cu0BCkEKGAgDEhRE3LlqsVHaEBe76rrfLgRINtZG8RITZGFub3BpYUBkYW5vcGlhLm5ldBoQCg5lY2hvZXlAa3NoaC51cxKnAQqAARKhWHLH9d3IyCDE7KihB58YsnYZqD4UDpzeVRB0F9bKGfyb8vaElXuJBWWmU1OEO6RJ25uzb9CTGhyR6Vrvm0loGhvOAkxYn0YpWpNvVADlpKt/x0xEi37FCRnf/d1/ojohnYRKBpQAHVx8nHbfTWXq+UYFXUSulX1u7TzrWJoFEiBKh82DtzpWdYSOlARbLgko9zAC/MQ1ezf1xGBxWBh3xRgBEhgIAxIURNy5arFR2hAXu+q63y4ESDbWRvEYASCfq66rxiQ=]]></applied-delta></wavelet-update></item></items></event></message>'
				end
			
			when name == 'message' && (type == 'normal' || !type)
				subtype = packet.children.first.name
				
				if subtype == 'received'
					if id == '9744-2'
						puts "#{from} ponged, attempting to send the cert.."
						sock.send_xml '<iq type="set" id="258-4" from="' + myname + '" to="' + from + '"><pubsub xmlns="http://jabber.org/protocol/pubsub"><publish node="signer"><item><signature xmlns="http://waveprotocol.org/protocol/0.2/waveserver" domain="' + mydomain + '" algorithm="SHA256"><certificate><![CDATA[' + certs[mydomain] + ']]></certificate></signature></item></publish></pubsub></iq>'
						
					elsif id == '4597-8'
						puts "#{from} ACK'ed the first delta."
						
					else
						puts "#{from} ACK'ed our previous packet."
					end
					
				end
				
		end
	end
end
