require 'protobuffer'

class WaveProtoBuffer < ProtoBuffer
	
	structure :hashed_version, {1 => varint(:version), 2 => string(:hash)}

	structure :delta, {
		1 => hashed_version(:applied_to),
		2 => string(:author),
		3 => [operation(:operations)]
	}
	
	
	structure :key_value_pair, {1 => string(:key), 2 => string(:value)}

	structure :key_value_update, {
		1 => string(:key),
		2 => string(:old_value), # absent field means that the attribute was
			# absent/the annotation was null.
		3 => string(:new_value), # absent field means that the attribute should be
			# removed/the annotation should be set to null.
	}


	structure :annotation_boundary, {
		1 => boolean(:empty),
		2 => [string(:end)], # MUST NOT have the same string twice
		3 => [:key_value_update]} # MUST NOT have two updates with the same key. MUST
			# NOT contain any of the strings listed in the 'end' field.

	structure :element_start, {
		1 => string(:type),
		2 => [key_value_pair(:attributes)] # MUST NOT have two pairs with the same key
	}

	structure :replace_attributes, {
		1 => boolean(:empty),
		2 => [key_value_pair(:old_attributes)], # MUST NOT have two pairs with the same key
		3 => [key_value_pair(:new_attributes)] #  MUST NOT have two pairs with the same key
	}

	structure :update_attributes, {
		1 => boolean(:empty),
		2 => [key_value_update(:updates)] # MUST NOT have two updates with the same key
	}
	
	structure :document_op, {
		1 => [mutate_component(:components)]}
			
	structure :mutate_component, {
		1 => :annotation_boundary,
		2 => string(:characters),
		3 => :element_start,
		4 => boolean(:element_end),
		5 => varint(:retain_item_count),
		6 => string(:delete_chars),
		7 => element_start(:delete_element_start),
		8 => boolean(:delete_element_end),
		9 => :replace_attributes,
		10 => :update_attributes}
			
	structure :mutate, {
		1 => string(:document_id), # always 'main' as far as I can tell
		2 => document_op(:mutation)}


	structure :operation, {
		1 => string(:added),
		2 => string(:removed),
		3 => :mutate,
		4 => boolean(:noop)}
	
	structure :delta_signature, {
		1 => string(:signature),
		2 => string(:signer_id),
		3 => varint(:signer_id_alg)} # 1 = SHA1-RSA
	
	structure :signed_delta, {
		1 => :delta,
		2 => delta_signature(:signature)} # 1 = SHA1-RSA

	structure :applied_delta, {
		1 => signed_delta,
		2 => hashed_version(:applied_to),
		3 => varint(:operations_applied),
		4 => varint(:timestamp)} # UNIX epoche * 1000 + milliseconds

end


require 'pp'
require 'base64'
def encode64(data)
	Base64.encode64(data).gsub("\n", '')
end
def decode64(data)
	Base64.decode64(data)
end

pp WaveProtoBuffer.parse(:applied_delta, decode64('CpoCCm4KGAgIEhQx3X/ZwLVoYmCSHtYeyrpV+hdFphITZGFub3BpYUBkYW5vcGlhLm5ldBo9GjsKBG1haW4SMwojGiEKBGxpbmUSGQoCYnkSE2Rhbm9waWFAZGFub3BpYS5uZXQKAiABCggSBkhlbGxvLhKnAQqAAU4UJk+x0QLJmRW4CnJmKTjT2Hl/FJuCl6BCbjVUSObZLPNj3rC2vvcCfiSlT3dhkCYEq9AOYHdJKdiwsix7joHql0NUfb53maNtiIPJxciHvBGndRlBpeBYtDHr2+3/VRXEBNF/stFc0w24LGOt+EBGfdrW/BAqbQUpOu4auDHEEiByaAt3Th3lnLa43WcJcmBiOabN2b5GGbpBhRe+/NkEKhgBEhgICBIUMd1/2cC1aGJgkh7WHsq6VfoXRaYYASDogNjwyCQ='))
puts
pp WaveProtoBuffer.parse(:delta, "\n\030\b\b\022\0241\335\177\331\300\265hb`\222\036\326\036\312\272U\372\027E\246\022\023danopia@danopia.net\032=\032;\n\004main\0223\n#\032!\n\004line\022\031\n\002by\022\023danopia@danopia.net\n\002 \001\n\b\022\006Hello.")
