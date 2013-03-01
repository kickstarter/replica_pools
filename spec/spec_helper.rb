require 'rubygems'
require 'bundler/setup'
require 'logger'

require 'slave_pools'

module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

SLAVE_POOLS_SPEC_DIR = File.dirname(__FILE__)
SLAVE_POOLS_SPEC_CONFIG = YAML::load(File.open(SLAVE_POOLS_SPEC_DIR + '/config/database.yml'))

ActiveRecord::Base.logger = Logger.new(SLAVE_POOLS_SPEC_DIR + "/debug.log")
ActiveRecord::Base.configurations = SLAVE_POOLS_SPEC_CONFIG
