require 'rubygems'
require 'bundler/gem_tasks'

require 'rspec/core/rake_task'

desc 'Default: run specs.'
task :default => :spec

desc 'Bootstrap MySQL configuration'
task :bootstrap do
  system 'mysql -u root mysql < spec/config/bootstrap.sql'
end

desc "Run specs"
RSpec::Core::RakeTask.new(spec: :bootstrap)
