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

    def initialize
      @environment        = (defined?(Rails.env) ? Rails.env : 'development')
      @master_models      = default_master_models
      @defaults_to_master = false
    end

    private

    def default_master_models
      if ActiveRecord.const_defined?(:SessionStore) # >= Rails 2.3
        ['ActiveRecord::SessionStore::Session']
      else # =< Rails 2.3
        ['CGI::Session::ActiveRecordStore::Session']
      end
    end
  end
end
