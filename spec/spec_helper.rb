require 'rubygems'
require 'bundler/setup'
require 'logger'

module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end

  module VERSION
    MAJOR = 3
  end
end

require 'slave_pools'
SlavePools::Engine.initializers.each(&:run)

spec_dir = File.dirname(__FILE__)
ActiveRecord::Base.logger = Logger.new(spec_dir + "/debug.log")
ActiveRecord::Base.configurations = YAML::load(File.open(spec_dir + '/config/database.yml'))

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
end

RSpec.configure do |c|
  c.include SlavePools::Testing
end
