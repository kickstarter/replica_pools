require 'rails/engine'

module SlavePools
  class Engine < Rails::Engine
    initializer 'slave_pools.defaults' do
      SlavePools.config.environment = Rails.env
    end

    config.after_initialize do
      SlavePools.setup!
    end
  end
end
