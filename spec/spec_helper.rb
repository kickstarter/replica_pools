require 'rubygems'
require 'bundler/setup'
require 'logger'

module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

require 'active_record'
spec_dir = File.dirname(__FILE__)
ActiveRecord::Base.logger = Logger.new(spec_dir + "/debug.log")
ActiveRecord::Base.configurations = YAML::load(File.open(spec_dir + '/config/database.yml'))

ActiveRecord::Base.establish_connection :test
ActiveRecord::Migration.verbose = false
ActiveRecord::Migration.create_table(:test_models, :force => true) {}
ActiveRecord::Migration.create_table(:test_subs, :force => true) {|t| t.integer :test_model_id}

require 'slave_pools'
SlavePools::Engine.initializers.each(&:run)
ActiveSupport.run_load_hooks(:after_initialize, SlavePools::Engine)

module SlavePools::Testing
  # Creates aliases for the slave connections in each pool
  # for easy reference in tests.
  def create_slave_aliases(proxy)
    proxy.slave_pools.each do |name, pool|
      pool.slaves.each.with_index do |slave, i|
        instance_variable_set("@#{name}_slave#{i + 1}", slave.retrieve_connection)
      end
    end
  end

  def reset_proxy(proxy)
    proxy.slave_pools.each{|_, pool| pool.reset }
    proxy.current_pool = proxy.slave_pools[:default]
    proxy.current      = proxy.current_slave
  end
end

RSpec.configure do |c|
  c.include SlavePools::Testing
end
