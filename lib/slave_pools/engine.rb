require 'rails/engine'

module SlavePools
  class Engine < Rails::Engine
    initializer 'slave_pools.defaults' do
      SlavePools.config.environment = Rails.env

      SlavePools.config.safe_methods =
        if Rails::VERSION::MAJOR == 3
          [
            :select_all, :select_one, :select_value, :select_values,
            :select_rows, :select, :verify!, :raw_connection, :active?, :reconnect!,
            :disconnect!, :reset_runtime, :log, :log_info
          ]
        else
          raise "Unsupported Rails version #{Rails.version}. Please whitelist the safe methods."
        end
    end

    config.after_initialize do
      SlavePools.setup!
    end
  end
end
