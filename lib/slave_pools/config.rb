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

    # enter a list of errors/messages that shouldn't fall back to master
    # of the form {ErrorClass => ['message regex1', 'message regex 2'], }
    # Defaults are {Mysql2::Error => ['Timeout waiting for a response from the last query']}.
    attr_accessor :no_replay_on_master

    def initialize
      @environment        = 'development'
      @defaults_to_master = false
      @safe_methods       = []
      @no_replay_on_master = {}
    end
  end
end
