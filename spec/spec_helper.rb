require 'rubygems'
require 'bundler/setup'
require 'logger'

ENV['MYSQL_PORT'] ||= %x(docker compose port mysql 3306)[/\d+$/]

module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

require 'active_record'
spec_dir = File.dirname(__FILE__)
ActiveRecord::Base.logger = Logger.new(spec_dir + "/debug.log")
ActiveRecord::Base.configurations = YAML::safe_load(ERB.new(File.read(spec_dir + '/config/database.yml')).result, aliases: true)
ActiveRecord::Base.establish_connection :test
ActiveRecord::Migration.verbose = false
ActiveRecord::Migration.create_table(:test_models, :force => true) {}

require 'replica_pools'
ReplicaPools::Engine.initializers.each(&:run)
ActiveSupport.run_load_hooks(:after_initialize, ReplicaPools::Engine)

module ReplicaPools::Testing
  # Creates aliases for the replica connections in each pool
  # for easy reference in tests.
  def create_replica_aliases(proxy)
    proxy.replica_pools.each do |name, pool|
      pool.replicas.each.with_index do |replica, i|
        instance_variable_set("@#{name}_replica#{i + 1}", replica.retrieve_connection)
      end
    end
  end

  def reset_proxy(proxy)
    proxy.replica_pools.each{|_, pool| pool.reset }
    proxy.current_pool = proxy.replica_pools[:default]
    proxy.current      = proxy.current_replica
  end
end

RSpec.configure do |c|
  c.include ReplicaPools::Testing

  # This gem mostly uses the old deprecated shoulda syntax. Support both versions for now.
  c.expect_with :rspec do |c|
    c.syntax = [:expect, :should]
  end
  c.mock_with :rspec do |c|
    c.syntax = [:expect, :should]
  end

  c.filter_run focus: true
  c.run_all_when_everything_filtered = true
end
