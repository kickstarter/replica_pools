require "bundler/gem_tasks"
require "yaml"
require 'rspec/core/rake_task'
require "pp"

desc 'Default: run specs.'
task :default => :spec

desc 'Bootstrap MySQL configuration'
task :bootstrap do
  config = YAML::load(ERB.new(File.read('spec/config/database.yml')).result)["test"]
  system("mysql --verbose --user=#{config["username"]} --host=#{config["host"]} --port=#{config["port"]} mysql < spec/config/bootstrap.sql")
end

desc "Run specs"
RSpec::Core::RakeTask.new(:spec)
