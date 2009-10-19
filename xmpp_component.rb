require 'socket'
require 'digest/sha1'

require 'rubygems'
require 'hpricot'

require 'socket'
require 'stringio'
sleep 2
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
		key = (data.getc-10)/8
		return if key == -2
		
		args = {}
		raw = StringIO.new(read_string(data))
		puts ('  '*tree.size) + "Parsing \##{key}. Tree: #{tree.join(' -> ')} Data: #{raw.string.inspect}"
		
		if raw.string[0] == 8 #|| (tree.size == 3 && tree[2] == 0 && key == 1)
			raw.getc if raw.string[0] == 8
			value = read_varint(raw)
			puts ('  '*tree.size) + "Int: #{value}"
			parent_args[key] ||= []
			parent_args[key] << value
			return if raw.eof?
		end
		
		if !(1..10).to_a.map{|num|(2+num*8)}.include?(raw.string[0])
			puts ('  '*tree.size) + "String: #{raw.string}"
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
				return value
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
				output << (type*8+10).chr
				if arg.is_a? Hash
					write_string output, write_args(arg)
				elsif arg.is_a? Fixnum
					output << write_varint(arg)
				else
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

data = "\n\355\001\nA\n\030\b\003\022\024D\334\271j\261Q\332\020\027\273\352\272\337.\004H6\326F\361\022\023danopia@danopia.net\032\020\n\016echoey@kshh.us\022\247\001\n\200\001\022\241Xr\307\365\335\310\310 \304\354\250\241\a\237\030\262v\031\250>\024\016\234\336U\020t\027\326\312\031\374\233\362\366\204\225{\211\005e\246SS\204;\244I\333\233\263o\320\223\032\034\221\351Z\357\233Ih\032\e\316\002LX\237F)Z\223oT\000\345\244\253\177\307LD\213~\305\t\031\337\375\335\372#\242\031\330D\240i@\001\325\307\311\307m\364\326^\257\224`U\324J\351W\326\356\323\316\265\211\240Q\"\004\250|\330;s\245gXH\351@E\262\340\222\217s\000/\314CW\263\177\\F\a\025\201\207|Q\200\021!\200\2001!DM\313\226\253\025\035\241\001{\276\253\255\362\340D\203mdo\021\200\022\t\372\272\352\274b@"

hash = ProtoBuffer.parse data
p hash
exit

#doc = Hpricot('<packet><iq type="get" id="513-92" from="component.danopia.net" to="wave.danopia.net"><query xmlns="http://jabber.org/protocol/disco#info"/></iq><iq type="get" id="513-92" from="component.danopia.net" to="wave.danopia.net"><query xmlns="http://jabber.org/protocol/disco#info"/></iq></packet>')

#p doc.root.children.first.name
#exit

sleep 5

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
sock.send_xml '<iq type="get" id="5328-0" to="kshh.us" from="' + myname + '"><query xmlns="http://jabber.org/protocol/disco#items"/></iq>'

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
