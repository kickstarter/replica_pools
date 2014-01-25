require 'rails/engine'

module SlavePools
  class Engine < Rails::Engine
    initializer 'slave_pools.defaults' do
      SlavePools.config.environment = Rails.env

      SlavePools.config.safe_methods =
        if ActiveRecord::VERSION::MAJOR == 3
          [
            :select_all, :select_one, :select_value, :select_values,
            :select_rows, :select, :verify!, :raw_connection, :active?, :reconnect!,
            :disconnect!, :reset_runtime, :log, :log_info
          ]
        elsif ActiveRecord::VERSION::MAJOR == 4
          [
            :select_all, :select_one, :select_value, :select_values,
            :select_rows, :select, :verify!, :raw_connection, :active?, :reconnect!,
            :disconnect!, :reset_runtime, :log
          ]
        else
          warn "Unsupported ActiveRecord version #{ActiveRecord.version}. Please whitelist the safe methods."
        end
    end

    config.after_initialize do
      SlavePools.setup!
    end
  end
end
