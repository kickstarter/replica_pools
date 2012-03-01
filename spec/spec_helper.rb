require 'rubygems'
gem 'activerecord', '3.0.10'
gem 'mysql2', '0.2.18'
%w[active_record yaml erb rspec logger].each {|lib| require lib}

module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

SLAVE_POOLS_SPEC_DIR = File.dirname(__FILE__)
SLAVE_POOLS_SPEC_CONFIG = YAML::load(File.open(SLAVE_POOLS_SPEC_DIR + '/config/database.yml'))

ActiveRecord::Base.logger = Logger.new(SLAVE_POOLS_SPEC_DIR + "/debug.log")
ActiveRecord::Base.configurations = SLAVE_POOLS_SPEC_CONFIG