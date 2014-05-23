require 'active_record/connection_adapters/abstract/query_cache'
require 'set'

module SlavePools
  class ConnectionProxy
    include SlavePools::QueryCache

    attr_accessor :master
    attr_accessor :master_depth, :current, :current_pool, :slave_pools

    class << self
      def generate_safe_delegations
        SlavePools.config.safe_methods.each do |method|
          generate_safe_delegation(method) unless instance_methods.include?(method)
        end
      end

      protected

      def generate_safe_delegation(method)
        class_eval <<-END, __FILE__, __LINE__ + 1
          def #{method}(*args, &block)
            route_to(current, :#{method}, *args, &block)
          end
        END
      end
    end

    def initialize(master, pools)
      @master       = master
      @slave_pools  = pools
      @master_depth = 0
      @current_pool = default_pool

      if SlavePools.config.defaults_to_master
        @current = master
      else
        @current = current_slave
      end

      # this ivar is for ConnectionAdapter compatibility
      # some gems (e.g. newrelic_rpm) will actually use
      # instance_variable_get(:@config) to find it.
      @config = current.connection_config
    end

    def with_pool(pool_name = 'default')
      last_conn, last_pool = self.current, self.current_pool
      self.current_pool = slave_pools[pool_name.to_sym] || default_pool
      self.current = current_slave unless within_master_block?
      yield
    ensure
      self.current_pool = last_pool
      self.current      = last_conn
    end

    def with_master
      last_conn = self.current
      self.current = master
      self.master_depth += 1
      yield
    ensure
      self.master_depth = [master_depth - 1, 0].max
      self.current = last_conn
    end

    def transaction(*args, &block)
      with_master { master.transaction(*args, &block) }
    end

    def next_slave!
      return if within_master_block?
      self.current = current_pool.next
    end

    def current_slave
      current_pool.current
    end

    protected

    def default_pool
      slave_pools[:default] || slave_pools.values.first
    end

    # Proxies any unknown methods to master.
    # Safe methods have been generated during `setup!`.
    # Creates a method to speed up subsequent calls.
    def method_missing(method, *args, &block)
      generate_unsafe_delegation(method)
      send(method, *args, &block)
    end

    def within_master_block?
      master_depth > 0
    end

    def generate_unsafe_delegation(method)
      self.class_eval <<-END, __FILE__, __LINE__ + 1
        def #{method}(*args, &block)
          route_to(master, :#{method}, *args, &block)
        end
      END
    end

    def route_to(conn, method, *args, &block)
      conn.retrieve_connection.send(method, *args, &block)
    rescue => e
      SlavePools.log :error, "Error during ##{method}: #{e}"
      log_proxy_state
      raise if conn == master

      if safe_to_replay(e)
        SlavePools.log :error, %(#{e.message}\n#{e.backtrace.join("\n")})
        SlavePools.log :error, "Replaying on master."
        route_to(master, method, *args, &block)
      else
        current.retrieve_connection.verify! # may reconnect
        raise e
      end
    end

    # decides whether to replay query against master based on the
    # exception and message.
    # These can be adjusted by setting SlavePools.configs.no_replay_on_master.
    def safe_to_replay(e)
      return true unless flagged_messages_for_error = SlavePools.config.no_replay_on_master[e.class]

      return false if flagged_messages_for_error.any? {|m| e.message.match(m)}

      true
    end

    private

    def log_proxy_state
      SlavePools.log :error, "Current Connection: #{current}"
      SlavePools.log :error, "Current Pool Name: #{current_pool.name}"
      SlavePools.log :error, "Current Pool Members: #{current_pool.slaves}"
      SlavePools.log :error, "Master Depth: #{master_depth}"
    end
  end
end
