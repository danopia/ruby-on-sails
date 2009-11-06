# Includes the lib/ files: wave_proto utils delta operations playback provider
# server remote wave

%w{wave_proto utils delta operations playback provider server remote wave}.each do |file|
	require File.join(File.dirname(__FILE__), 'lib', file)
end

