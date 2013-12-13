module SlavePools
  class Config
    # defaults to Rails.env if slave_pools is used with Rails
    # defaults to 'development' when used outside Rails
    attr_accessor :environment

    # a list of models that should always go directly to the master
    #
    # Example:
    #
    #   SlavePool.config.master_models = ['MySessionStore', 'PaymentTransaction']
    attr_accessor :master_models

    # if master should be the default db
    attr_accessor :defaults_to_master

    # a list of methods that are safe to send to a readonly connection
    # must be declared before setup!
    attr_accessor :safe_methods

    def initialize
      @environment        = (defined?(Rails.env) ? Rails.env : 'development')
      @master_models      = default_master_models
      @defaults_to_master = false
      @safe_methods       = default_safe_methods
    end

    private

    def default_master_models
      if ActiveRecord.const_defined?(:SessionStore) # >= Rails 2.3
        ['ActiveRecord::SessionStore::Session']
      else # =< Rails 2.3
        ['CGI::Session::ActiveRecordStore::Session']
      end
    end

    def default_safe_methods
      return [] unless defined? Rails
      if Rails::VERSION::MAJOR == 3
        Set.new([
          :select_all, :select_one, :select_value, :select_values,
          :select_rows, :select, :verify!, :raw_connection, :active?, :reconnect!,
          :disconnect!, :reset_runtime, :log, :log_info
        ])
      else
        raise "Unsupported Rails version #{Rails.version}. Please whitelist the safe methods."
      end
    end
  end
end
