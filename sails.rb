# Includes all the libs

%w{wave_proto utils delta operations playback provider server remote wave}.each do |file|
	require File.join(File.dirname(__FILE__), 'lib', file)
end

