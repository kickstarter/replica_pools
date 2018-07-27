require "bundler/gem_tasks"

require 'rspec/core/rake_task'

desc 'Default: run specs.'
task :default => :spec

desc 'Bootstrap MySQL configuration'
task :bootstrap do
  puts "executing spec/config/bootstrap.sql\n\n"
  system('mysql --verbose --user=root --host=127.0.0.1 --port=3309 mysql < spec/config/bootstrap.sql')
end

desc "Run specs"
RSpec::Core::RakeTask.new(:spec)
