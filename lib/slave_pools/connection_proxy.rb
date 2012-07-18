require 'active_record/connection_adapters/abstract/query_cache'

module SlavePoolsModule
  class ConnectionProxy
    include ActiveRecord::ConnectionAdapters::QueryCache
    include QueryCacheCompat
    
    # Safe methods are those that should either go to the slave ONLY or go
    # to the current active connection.
    SAFE_METHODS = [ :select_all, :select_one, :select_value, :select_values, 
      :select_rows, :select, :verify!, :raw_connection, :active?, :reconnect!,
      :disconnect!, :reset_runtime, :log, :log_info ]

    if ActiveRecord.const_defined?(:SessionStore) # >= Rails 2.3
      DEFAULT_MASTER_MODELS = ['ActiveRecord::SessionStore::Session']
    else # =< Rails 2.3
      DEFAULT_MASTER_MODELS = ['CGI::Session::ActiveRecordStore::Session']
    end

    attr_accessor :master
    attr_accessor :master_depth, :current, :current_pool
    
    
    class << self
      
      # defaults to Rails.env if multi_db is used with Rails
      # defaults to 'development' when used outside Rails
      attr_accessor :environment
      
      # a list of models that should always go directly to the master
      #
      # Example:
      #
      #  SlavePool::ConnectionProxy.master_models = ['MySessionStore', 'PaymentTransaction']
      attr_accessor :master_models
      
      #true or false - whether you want to include the ActionController helpers or not
      #this allow
      
      # if master should be the default db
      attr_accessor :defaults_to_master
      
      # #setting a config instance variable so that thinking sphinx,and other gems that use the connection.instance_variable_get(:@config), work correctly
      attr_accessor :config

      # Replaces the connection of ActiveRecord::Base with a proxy and
      # establishes the connections to the slaves.
      def setup!
        self.master_models ||= DEFAULT_MASTER_MODELS
        self.environment   ||= (defined?(Rails.env) ? Rails.env : 'development')    
        
        slave_pools = init_slave_pools
        # if there are no slave pools, we just want to silently exit and not edit the ActiveRecord::Base.connection
        if !slave_pools.empty?
          master = ActiveRecord::Base
          master.send :include, SlavePoolsModule::ActiveRecordExtensions
          ActiveRecord::Observer.send :include, SlavePoolsModule::ObserverExtensions
          
          master.connection_proxy = new(master, slave_pools)
          master.logger.info("** slave_pools with master and #{slave_pools.length} slave_pool#{"s" if slave_pools.length > 1} (#{slave_pools.keys}) loaded.")
        else
          ActiveRecord::Base.logger.info(" No Slave Pools specified for this environment") #this is currently not logging
        end
      end
      
      protected
      
      def init_slave_pools
        slave_pools = {}
        ActiveRecord::Base.configurations.each do |name, db_config|
          # look for dbs matching the slave_pool format and verify a test connection before adding it to the pools
          if name.to_s =~ /#{self.environment}_pool_(.*)_name_(.*)/ && connection_valid?(db_config)
            slave_pools = add_to_pool(slave_pools, $1, $2, name, db_config)
          end
        end
        return slave_pools
      end
      
      private :new
      
    end # end class << self

    def initialize(master, slave_pools)
      @slave_pools = {}
      slave_pools.each do |pool_name, slaves|
        @slave_pools[pool_name.to_sym] = SlavePool.new(pool_name, slaves)
      end
      @master    = master
      @reconnect = false
      @current_pool = default_pool
      if self.class.defaults_to_master
        @current = @master
        @master_depth = 1
        @config = master.connection.instance_variable_get(:@config)
      else
        @current = slave
        @master_depth = 0
        @config = @current.config_hash #setting this 
      end
      
    end
    
    def default_pool
      @slave_pools[:default] || @slave_pools.values.first #if there is no default specified, use the first pool found
    end
    
    def slave_pools
      @slave_pools
    end

    def slave
      @current_pool.current
    end
    
    def with_pool(pool_name = 'default')
      @current_pool = @slave_pools[pool_name.to_sym] || default_pool
      @current = slave unless within_master_block?
      yield
    ensure
      @current_pool = default_pool
      @current = slave unless within_master_block?
    end
    
    def with_master
      @current = @master
      @master_depth += 1
      yield
    ensure
      @master_depth -= 1
      @master_depth = 0 if @master_depth < 0 # ensure that master depth never gets below 0
      @current = slave if !within_master_block?
    end
    
    def within_master_block?
      @master_depth > 0
    end

    def transaction(start_db_transaction = true, &block)
      with_master { @master.retrieve_connection.transaction(start_db_transaction, &block) }
    end

    # Calls the method on master/slave and dynamically creates a new
    # method on success to speed up subsequent calls
    def method_missing(method, *args, &block)
      send(target_method(method), method, *args, &block).tap do 
        create_delegation_method!(method)
      end
    end

    # Switches to the next slave database for read operations.
    # Fails over to the master database if all slaves are unavailable.
    def next_slave!
      return if within_master_block? # don't if in with_master block
      @current = @current_pool.next
    rescue
      @current = @master
    end

   protected

    def create_delegation_method!(method)
      self.instance_eval %Q{
        def #{method}(*args, &block)
          #{target_method(method)}(:#{method}, *args, &block)
        end
      }, __FILE__, __LINE__
    end
    
    def target_method(method)
      unsafe?(method) ? :send_to_master : :send_to_current
    end
    
    def send_to_master(method, *args, &block)
      reconnect_master! if @reconnect
      @master.retrieve_connection.send(method, *args, &block)
    rescue => e
      log_errors(e, 'send_to_master', method)
      raise_master_error(e)
    end
    
    def send_to_current(method, *args, &block)
      reconnect_master! if @reconnect && master?
      # logger.debug "[SlavePools] Using #{@current.name}"
      @current = @master if unsafe?(method) #failsafe to avoid sending dangerous method to master
      @current.retrieve_connection.send(method, *args, &block)
    rescue NotImplementedError, NoMethodError
      raise
    rescue => e # TODO don't rescue everything
      log_errors(e, 'send_to_current', method)
      raise_master_error(e) if master?
      logger.warn "[SlavePools] Error reading from slave database"
      logger.error %(#{e.message}\n#{e.backtrace.join("\n")})
      send_to_master(method, *args, &block) # if cant connect, send the query to master
    end
    
    def reconnect_master!
      @master.retrieve_connection.reconnect!
      @reconnect = false
    end
    
    def raise_master_error(error)
      logger.fatal "[SlavePools] Error accessing master database. Scheduling reconnect"
      @reconnect = true
      raise error
    end
    
    def unsafe?(method)
      !SAFE_METHODS.include?(method)
    end
    
    def master?
      @current == @master
    end
        
    def logger
      ActiveRecord::Base.logger
    end
    
    private
    
    def self.add_to_pool(slave_pools, pool_name, slave_name, full_db_name, db_config)
      slave_pools[pool_name] ||= []
      db_config_with_symbols = db_config.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
      SlavePoolsModule.module_eval %Q{
        class #{pool_name.camelize}#{slave_name.camelize} < ActiveRecord::Base
          self.abstract_class = true
          establish_connection :#{full_db_name}
          def self.config_hash 
            #{db_config_with_symbols.inspect}
          end 
        end
      }, __FILE__, __LINE__
      slave_pools[pool_name] << "SlavePoolsModule::#{pool_name.camelize}#{slave_name.camelize}".constantize
      return slave_pools
    end
    
    # method to verify whether DB connection is active?
    def self.connection_valid?(db_config = nil)
      is_connected = false
      if db_config
        begin
          ActiveRecord::Base.establish_connection(db_config)
          ActiveRecord::Base.connection
          is_connected = ActiveRecord::Base.connected?
          ActiveRecord::Base.establish_connection(environment) #rollback to the current environment to avoid issues
        rescue => e
          log_errors(e, 'self.connection_valid?')
        end
      end
      return is_connected
    end

    # logging instance errors
    def log_errors(error, sp_method, db_method)
      logger.error "[SlavePools] - Error: #{error}"
      logger.error "[SlavePools] - SlavePool Method: #{sp_method}"
      logger.error "[SlavePools] - Master Value: #{@master}"
      logger.error "[SlavePools] - Master Depth: #{@master_depth}"
      logger.error "[SlavePools] - Current Value: #{@current}"
      logger.error "[SlavePools] - Current Pool: #{@current_pool}"
      logger.error "[SlavePools] - Current Pool Slaves: #{@current_pool.slaves}"
      logger.error "[SlavePools] - Current Pool Name: #{@current_pool.name}"
      logger.error "[SlavePools] - Reconnect Value: #{@reconnect}"
      logger.error "[SlavePools] - Default Pool: #{default_pool}"
      logger.error "[SlavePools] - DB Method: #{db_method}"
    end

    # logging class errors
    def self.log_errors(error, sp_method)
      logger = ActiveRecord::Base.logger
      logger.error "[SlavePools] - Error: #{error}"
      logger.error "[SlavePools] - SlavePool Method: #{sp_method}"
    end
  end
end