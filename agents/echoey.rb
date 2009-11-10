class Echoey# < Sails::Agent
	def handle remote, wave, blip
		if blip
			@wave.build_delta 'echoey@danopia.net' do
				new_blip_under blip, blip.digest
			end
		end
	end
end
