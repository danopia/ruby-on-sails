require File.join(File.dirname(__FILE__), 'protobuffer')

module Sails

# Defines a Google Wave ProtoBuffer.
class ProtoBuffer < ProtoBuffer

	##########################
	# Core structures
	##########################
	structure :hashed_version, {
		1 => varint(:version),
		2 => string(:hash)
	}

	structure :delta_signature, {
		1 => string(:signature),
		2 => string(:signer_id),
		3 => varint(:signer_id_alg) # 1 = SHA1-RSA
	}
	
	structure :signed_delta, {
		1 => delta,
		2 => delta_signature(:signature) # 1 = SHA1-RSA
	}

	structure :applied_delta, {
		1 => signed_delta,
		2 => hashed_version(:applied_to),
		3 => varint(:operations_applied),
		4 => varint(:timestamp) # UNIX epoche * 1000 + milliseconds
	}

	structure :delta, {
		1 => hashed_version(:applied_to),
		2 => string(:author),
		3 => [operation(:operations)]
	}
	
	##########################
	# Operation structures
	##########################
	structure :mutate, {
		1 => string(:document_id), # always 'main' as far as I can tell
		2 => document_op(:mutation)
	}


	structure :operation, {
		1 => string(:added),
		2 => string(:removed),
		3 => mutate,
		4 => boolean(:noop) # nothing happened
	}
	
	##########################
	# Mutation structures
	##########################
	structure :key_value_pair, {
		1 => string(:key),
		2 => string(:value)
	}

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
		3 => [key_value_update] # MUST NOT have two updates with the same key. MUST
			# NOT contain any of the strings listed in the 'end' field.
	}

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
	
	
	structure :document_op, {1 => [mutate_component(:components)]} # Lol?
			
	structure :mutate_component, {
		1 => annotation_boundary,
		2 => string(:characters),
		3 => element_start,
		4 => boolean(:element_end),
		5 => varint(:retain_item_count),
		6 => string(:delete_chars),
		7 => element_start(:delete_element_start),
		8 => boolean(:delete_element_end),
		9 => replace_attributes,
		10 => update_attributes
	}
end # class

end # module

