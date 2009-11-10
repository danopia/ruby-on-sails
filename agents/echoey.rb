class Echoey# < Sails::Agent
	def handle remote, wave, blip
		if blip
			Sails::Delta.build remote, wave, 'echoey@danopia.net' do |builder|
				builder.new_blip_under blip, blip.contents.gsub("\001", '')
			end
		end
	end
end
