require 'rubygems'
require 'yaml'

module Sails

module Utils

	def self.connect_db
		require 'active_record'
		require 'logger'

		dbconfig = YAML.load(open(File.join(File.dirname(__FILE__), '..', 'database.yml')))
		dbconfig = dbconfig['development']
		dbconfig['database'] = 'rails/' + dbconfig['database'] if dbconfig['adapter'] == 'sqlite'

		ActiveRecord::Base.establish_connection dbconfig
		ActiveRecord::Base.logger = Logger.new(STDERR)

		load_models
		
		true
	end
	
	def self.load_models
		return if @models_loaded
		@models_loaded = true
		
		require 'authlogic' # for the User model
		
		#require File.join(File.dirname(__FILE__), '..', 'models', 'server')
		
		Dir.glob(File.join(File.dirname(__FILE__), '..', 'models', '*.rb')).each do |model|
			require model
		end
	end
end

end # module
