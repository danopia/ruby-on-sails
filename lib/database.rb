require 'rubygems'
require 'active_record'
require 'yaml'
#require 'authlogic'
#require 'models/user'

puts 'hi'

module Sails

class Database

	def self.connect
		dbconfig = YAML.load(open(File.join(File.dirname(__FILE__), '..', 'database.yml')))
		dbconfig = dbconfig['development']
		dbconfig['database'] = 'rails/' + dbconfig['database'] if dbconfig['adapter'] == 'sqlite'

		ActiveRecord::Base.establish_connection dbconfig
		
		require 'authlogic'
		require 'models/user'
	end
	
end # class

end # module
