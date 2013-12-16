require 'rails/engine'

module SlavePools
  class Engine < Rails::Engine
    initializer 'slave_pools.defaults' do
      SlavePools.config.environment = Rails.env
    end
  end
end
