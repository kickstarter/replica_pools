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
          %i[
            active?
            disconnect!
            log
            log_info
            raw_connection
            reconnect!
            reset_runtime
            select
            select_all
            select_one
            select_rows
            select_value
            select_values
            verify!
          ]
        elsif ActiveRecord::VERSION::MAJOR == 4
          %i[
            active?
            disconnect!
            log
            raw_connection
            reconnect!
            reset_runtime
            select
            select_all
            select_one
            select_rows
            select_value
            select_values
            verify!
          ]
        elsif [5, 6].include?(ActiveRecord::VERSION::MAJOR)
          %i[
           active?
           cacheable_query
           case_insensitive_comparison
           case_sensitive_comparison
           clear_cache!
           column_name_for_operation
           combine_bind_parameters
           disconnect!
           log
           lookup_cast_type_from_column
           prepared_statements
           quote
           quote_column_names
           quote_table_name
           quote_table_names
           raw_connection
           reconnect!
           reset_runtime
           sanitize_limit
           schema_cache
           select
           select_all
           select_one
           select_prepared
           select_rows
           select_value
           select_values
           table_alias_for
           verify!
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
