# Includes the lib/ files: wave_proto utils delta operations playback provider
# server remote wave blip

%w{wave_proto utils delta operations playback provider server remote wave blip}.each do |file|
	require File.join(File.dirname(__FILE__), 'lib', file)
end

