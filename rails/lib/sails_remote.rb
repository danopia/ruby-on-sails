if defined? Rails
	files = ['sails_remote']
	files.each do |file|
		require Rails.root.join('..', 'lib', file)
	end
end
