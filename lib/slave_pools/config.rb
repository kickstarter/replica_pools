module SlavePools
  class Config
    # The current environment. Normally set to Rails.env, but
    # will default to 'development' outside of Rails apps.
    attr_accessor :environment

    # When true, all queries will go to master unless wrapped in with_pool{}.
    # When false, all safe queries will go to the current replica unless wrapped in with_master{}.
    # Defaults to false.
    attr_accessor :defaults_to_master

    # The list of methods considered safe to send to a readonly connection.
    # Defaults are based on Rails version.
    attr_accessor :safe_methods

    def initialize
      @environment        = 'development'
      @defaults_to_master = false
      @safe_methods       = []
    end
  end
end
