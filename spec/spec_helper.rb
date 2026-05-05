require 'rubygems'
require 'bundler/setup'
require 'active_support/all'
require 'active_record'
require 'erb'
require 'logger'
require 'yaml'

ENV['MYSQL_PORT'] ||= %x(docker compose port mysql 3306)[/\d+$/]

module Rails
  class << self
    attr_writer :logger

    def env
      ActiveSupport::StringInquirer.new('test')
    end

    def logger
      @logger ||= Logger.new($stdout)
    end
  end
end

ActiveRecord::Base.logger = Logger.new(File.join(__dir__, 'debug.log'))
ActiveRecord::Base.configurations = YAML.safe_load(
  ERB.new(File.read(File.join(__dir__, 'config/database.yml'))).result,
  aliases: true,
)
ActiveRecord::Base.establish_connection(:test)
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  suppress_messages do
    create_table(:test_models, force: true) do |t|
      t.string :key
      t.integer :value
      t.timestamps null: false
    end
  end
end

ActiveRecord::Base.connects_to(
  shards: {
    default: {
      writing: :test,
      reading: :test_pool_default_name_1,
    },
    admin: {
      writing: :test,
      reading: :test_pool_admin_name_1,
    },
  },
)

require 'replica_pools'
require_relative 'config/test_model'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.syntax = [:expect]
  end

  config.mock_with :rspec do |mocks|
    mocks.syntax = [:expect]
  end
end
