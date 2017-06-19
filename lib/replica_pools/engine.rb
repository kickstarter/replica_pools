require 'rails/engine'

module ReplicaPools
  class Engine < Rails::Engine
    # the :finisher_hook initializer is what runs :after_initializer
    # callbacks. we want to guarantee that this configuration happens
    # before `setup!` no matter what else happens to initializer order.
    initializer 'replica_pools.defaults', before: :finisher_hook do
      ReplicaPools.config.environment = Rails.env

      ReplicaPools.config.safe_methods =
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
        elsif ActiveRecord::VERSION::MAJOR == 5
          [
           :select_all, :select_one, :select_value, :select_values,
           :select_rows, :select, :select_prepared, :verify!, :raw_connection,
           :active?, :reconnect!, :disconnect!, :reset_runtime, :log
          ]
        else
          warn "Unsupported ActiveRecord version #{ActiveRecord.version}. Please whitelist the safe methods."
        end
    end

    config.after_initialize do
      ReplicaPools.setup!
    end
  end
end
