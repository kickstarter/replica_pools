require 'rubygems'
require 'bundler/setup'

require 'rspec/core/rake_task'

desc 'Default: run specs.'
task :default => :spec

desc 'Bootstrap MySQL configuration'
task :bootstrap do
  `mysql < spec/config/bootstrap.sql`
end

desc "Run specs"
RSpec::Core::RakeTask.new(spec: :bootstrap)
