require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'yaml'

desc 'Default: run specs.'
task :default => :spec

desc 'Bootstrap MySQL configuration'
task :bootstrap do
  sh %{docker compose exec -T mysql mysql < spec/config/bootstrap.sql}
end

desc 'Run specs'
RSpec::Core::RakeTask.new(:spec)
