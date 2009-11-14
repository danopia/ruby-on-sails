# Includes the lib/ files: wave_proto utils delta delta_builder operations playback provider
# server remote wave blip annotation thread

%w{wave_proto utils delta delta_builder operations playback provider server remote wave blip annotation thread}.each do |file|
	require File.join(File.dirname(__FILE__), 'lib', file)
end

