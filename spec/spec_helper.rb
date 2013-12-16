require 'rubygems'
require 'bundler/setup'
require 'logger'

require 'slave_pools'

module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end

  module VERSION
    MAJOR = 3
  end
end

SLAVE_POOLS_SPEC_DIR = File.dirname(__FILE__)
SLAVE_POOLS_SPEC_CONFIG = YAML::load(File.open(SLAVE_POOLS_SPEC_DIR + '/config/database.yml'))

ActiveRecord::Base.logger = Logger.new(SLAVE_POOLS_SPEC_DIR + "/debug.log")
ActiveRecord::Base.configurations = SLAVE_POOLS_SPEC_CONFIG

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
