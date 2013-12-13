require 'active_record/connection_adapters/abstract/query_cache'
require 'set'

module SlavePools
  class ConnectionProxy
    include ActiveRecord::ConnectionAdapters::QueryCache
    include QueryCacheCompat

    attr_accessor :master
    attr_accessor :master_depth, :current, :current_pool, :slave_pools

    class << self
      # Replaces the connection of ActiveRecord::Base with a proxy and
      # establishes the connections to the slaves.
      def setup!
        # if there are no slave pools, we just want to silently exit and not edit the ActiveRecord::Base.connection
        if slave_pools.empty?
          SlavePools.logger.info("[SlavePools] No slave pools found for #{SlavePools.config.environment}")
          return
        end

        master = ActiveRecord::Base
        master.send :include, SlavePools::ActiveRecordExtensions
        ActiveRecord::Observer.send :include, SlavePools::ObserverExtensions

        master.connection_proxy = new(master, slave_pools)
        SlavePools.logger.info("[SlavePools] slave_pools with master and #{slave_pools.length} slave_pool#{"s" if slave_pools.length > 1} (#{slave_pools.keys}) loaded.")
      end
      private :new

      protected

      # each pool is a set of connection classes
      def slave_pools
        @slave_pools ||= Hash.new{|h, k| h[k] = [] }.tap do |pools|
          slave_pool_configurations.each do |conn_name, pool_name, slave_name|
            pools[pool_name] << connection_class(pool_name, slave_name, conn_name)
          end
        end
      end

      # finds valid slave pool configs
      def slave_pool_configurations
        ActiveRecord::Base.configurations.map do |name, config|
          next unless name.to_s =~ /#{SlavePools.config.environment}_pool_(.*)_name_(.*)/
          next unless connection_valid?(config)
          [name, $1, $2]
        end.compact
      end

      # generates a unique ActiveRecord::Base subclass for a single slave
      def connection_class(pool_name, slave_name, connection_name)
        class_name = "#{pool_name.camelize}#{slave_name.camelize}"

        SlavePools.module_eval %Q{
          class #{class_name} < ActiveRecord::Base
            self.abstract_class = true
            establish_connection :#{connection_name}
            def self.connection_config
              configurations[#{connection_name.to_s.inspect}]
            end
          end
        }, __FILE__, __LINE__
        SlavePools.const_get(class_name)
      end

      # tests a connection to be sure it's configured
      def connection_valid?(db_config)
        ActiveRecord::Base.establish_connection(db_config)
        return ActiveRecord::Base.connection && ActiveRecord::Base.connected?
      rescue => e
        SlavePools.logger.error "[SlavePools] - Could not connect to #{db_config.inspect}"
        SlavePools.logger.error "[SlavePools] - #{e}"
        return false
      ensure
        ActiveRecord::Base.establish_connection(SlavePools.config.environment)
      end

    end # end class << self

    def initialize(master, slave_pools)
      @slave_pools = slave_pools.inject({}) do |h, (name, pool)|
        h.merge!(name.to_sym => SlavePool.new(name, pool))
      end
      @master       = master
      @master_depth = 0
      @reconnect    = false
      @current_pool = default_pool

      if SlavePools.config.defaults_to_master
        @current = @master
        @master_depth = 1
      else
        @current = slave
      end

      # this ivar is for ConnectionAdapter compatibility
      # some gems (e.g. newrelic_rpm) will actually use
      # instance_variable_get(:@config) to find it.
      @config = current.connection_config
    end

    def with_pool(pool_name = 'default')
      self.current_pool = slave_pools[pool_name.to_sym] || default_pool
      self.current = slave unless within_master_block?
      yield
    ensure
      self.current_pool = default_pool
      self.current = slave unless within_master_block?
    end

    def with_master
      self.current = master
      self.master_depth += 1
      yield
    ensure
      self.master_depth = [master_depth - 1, 0].max # ensure that master depth never gets below 0
      self.current = slave unless within_master_block?
    end

    def transaction(*args, &block)
      with_master { master.transaction(*args, &block) }
    end

    # Switches to the next slave database for read operations.
    # Fails over to the master database if all slaves are unavailable.
    def next_slave!
      return if within_master_block? # don't if in with_master block
      self.current = current_pool.next
    rescue
      self.current = master
    end

    protected

    def slave
      current_pool.current
    end

    def default_pool
      slave_pools[:default] || slave_pools.values.first #if there is no default specified, use the first pool found
    end

    # Calls the method on master/slave and dynamically creates a new
    # method on success to speed up subsequent calls
    def method_missing(method, *args, &block)
      create_delegation_method!(method)
      send(method, *args, &block)
    end

    def within_master_block?
      master_depth > 0
    end

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
      master.retrieve_connection.send(method, *args, &block)
    rescue => e
      log_errors(e, 'send_to_master', method)
      raise_master_error(e)
    end

    def send_to_current(method, *args, &block)
      reconnect_master! if @reconnect && master?
      # logger.debug "[SlavePools] Using #{current.name}"
      self.current = master if unsafe?(method) #failsafe to avoid sending dangerous method to master
      current.retrieve_connection.send(method, *args, &block)
    rescue Mysql2::Error, ActiveRecord::StatementInvalid => e
      log_errors(e, 'send_to_current', method)
      raise_master_error(e) if master?
      logger.warn "[SlavePools] Error reading from slave database"
      logger.error %(#{e.message}\n#{e.backtrace.join("\n")})
      if e.message.match(/Timeout waiting for a response from the last query/)
        # Verify that the connection is active & re-raise
        logger.error "[SlavePools] Slave Query Timeout - do not send to master"
        current.retrieve_connection.verify!
        raise e
      else
        logger.error "[SlavePools] Slave Query Error - sending to master"
        send_to_master(method, *args, &block) # if cant connect, send the query to master
      end
    end

    def reconnect_master!
      master.retrieve_connection.reconnect!
      @reconnect = false
    end

    def raise_master_error(error)
      logger.fatal "[SlavePools] Error accessing master database. Scheduling reconnect"
      @reconnect = true
      raise error
    end

    def unsafe?(method)
      !SlavePools.config.safe_methods.include?(method)
    end

    def master?
      current == master
    end

    private

    def logger
      SlavePools.logger
    end

    def log_errors(error, sp_method, db_method)
      logger.error "[SlavePools] - Error: #{error}"
      logger.error "[SlavePools] - SlavePool Method: #{sp_method}"
      logger.error "[SlavePools] - Master Value: #{master}"
      logger.error "[SlavePools] - Master Depth: #{master_depth}"
      logger.error "[SlavePools] - Current Value: #{current}"
      logger.error "[SlavePools] - Current Pool: #{current_pool}"
      logger.error "[SlavePools] - Current Pool Slaves: #{current_pool.slaves}" if current_pool
      logger.error "[SlavePools] - Current Pool Name: #{current_pool.name}" if current_pool
      logger.error "[SlavePools] - Reconnect Value: #{@reconnect}"
      logger.error "[SlavePools] - Default Pool: #{default_pool}"
      logger.error "[SlavePools] - DB Method: #{db_method}"
    end
  end
end
