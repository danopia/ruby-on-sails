#!/usr/bin/env ruby

require 'core.rb'

source = "\342\000\000\000\001 waveserver.ProtocolWaveletUpdate\277\001\n,wave://danopia.net/!indexwave/w+mc0XHEuVBnTZ\022)\n\004\b\000\022\000\022\rdigest-author\032\022\032\020\n\006digest\022\006\n\004\022\002hi\022,\n\004\b\001\022\000\022\020test@danopia.net\032\022\n\020test@danopia.net\022/\n\004\b\002\022\000\022\020test@danopia.net\032\025\n\023danopia@danopia.net\"\004\b\003\022\000"
source = "f\000\000\000\002\036waveserver.ProtocolOpenRequestE\n\020test@danopia.net\022\032danopia.net!w+mc0XHEuVBnTZ\032\025danopia.net!conv+root"
source = "o\001\000\000\002 waveserver.ProtocolWaveletUpdate\313\002\n+wave://danopia.net/w+mc0XHEuVBnTZ/conv+root\022W\n/\b\000\022+wave://danopia.net/w+mc0XHEuVBnTZ/conv+root\022\020test@danopia.net\032\022\n\020test@danopia.net\022C\n\030\b\001\022\024\243+\223\235W\311\245#h\016\265P\t\262y\217\271V\366\244\022\020test@danopia.net\032\025\n\023danopia@danopia.net\022d\n\030\b\002\022\024i\006k\220\370\372SK\314g#9\372\201~\364\2570\224A\022\020test@danopia.net\0326\0324\n\004main\022,\n \032\036\n\004line\022\026\n\002by\022\020test@danopia.net\n\002 \001\n\004\022\002hi\"\030\b\003\022\024\206Ok\223Kq,#\312!3\226\034\255\377\245}\004\305\035"

source = "\344\000\000\000\b waveserver.ProtocolSubmitRequest\300\001\n+wave://danopia.net/w+mc0XHEuVBnTZ/conv+root\022\220\001\n\030\b\003\022\024\206Ok\223Kq,#\312!3\226\034\255\377\245}\004\305\035\022\023danopia@danopia.net\032_\032]\n\004main\022U\n\002(\004\n#\032!\n\004line\022\031\n\002by\022\023danopia@danopia.net\n\002 \001\n&\022$This is an epic test. Really. It is." # send message

# \342\000\000\000
# \001
# " "waveserver.ProtocolWaveletUpdate
#		\276
#			\001
#
#			\n # wavelet_name (1, string)
#			,wave://danopia.net/!indexwave/w+mc0XHEuVBnTZ
#
#			\022 # applied_delta (2, string)
#			)\n\004\b\000\022\000\022\rdigest-author\032\022\032\020\n\006digest\022\006\n\004\022\002hi
#				version (1, string)
#				\004\b\000\022\000
#
#				author (2, string)
#				\rdigest-author
#
#				operations (3, string)
#				\022\032\020\n\006digest\022\006\n\004\022\002hi
#					add person (1, string)
#
#					remove person (2, string)
#
#					change content (3, string)
#					\020\n\006digest\022\006\n\004\022\002hi
#						doc id (1, string)
#						\006digest
#
#						operation (2, repeated string)
#						\006\n\004\022\002hi
#							annotation_boundary (1, byte?)
#							\004
#
#							characters (2, string)
#							\002hi
#							
#					noop (4, bool)
#
#			\022 # applied_delta (2, string)
#			\n\004\b\001\022\000\022\020test@danopia.net\032\022\n\020test@danopia.net
#				version (1, string)
#				\004\b\001\022\000
#
#				author (2, string)
#				\020test@danopia.net
#
#				operations (3, string)
#				\022\n\020test@danopia.net
#					add person (1, string)
#					\020test@danopia.net
#
#			\022 # applied_delta (2, string)
#			\n\004\b\002\022\000\022\020test@danopia.net\032\025\n\023danopia@danopia.net
#				version (1, string)
#				\004\b\002\022\000
#
#				author (2, string)
#				\020test@danopia.net
#
#				operations (3, string)
#				\025\n\023danopia@danopia.net
#					add person (1, string)
#					\023danopia@danopia.net
#
#			\032 # version commited to disk (3, optional string)
#
#			\" # resultant version (4, string)
#			\004\b\003\022\000
#

packet = Packet.parse StringIO.new(source)
p packet
p packet.to_s
p packet.to_s == source
