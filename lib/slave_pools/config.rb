module SlavePools
  class Config
    # The current environment. Normally set to Rails.env, but
    # will default to 'development' outside of Rails apps.
    attr_accessor :environment

    # When true, all queries will go to master unless wrapped in with_pool{}.
    # When false, all safe queries will go to the current slave unless wrapped in with_master{}.
    # Defaults to false.
    attr_accessor :defaults_to_master

    # The list of methods considered safe to send to a readonly connection.
    # Defaults are based on Rails version.
    attr_accessor :safe_methods

    def initialize
      @environment        = 'development'
      @defaults_to_master = false
      @safe_methods       = default_safe_methods
    end

    private

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
