require 'rake'

task :default => ['provider:start']

desc 'Start the provider as a XMPP component'
task 'provider:start' do
	ruby 'xmpp_component.rb'
end

desc 'Start a thin instance, in the background'
task 'thin:start' do
	sh 'thin start -dR rack.ru'
end

desc 'Start a thin instance, in the foreground'
task 'thin:fg' do
	sh 'thin start -R rack.ru'
end

desc 'Stop an instance of thin that was started in the background'
task 'thin:stop' do
	sh 'thin stop'
end

desc 'Restart the running thin instance (if none, just starts one)'
task 'thin:restart' => ['thin:stop', 'thin:start']
