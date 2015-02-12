require 'active_record/connection_adapters/abstract/query_cache'
require 'set'

module ReplicaPools
  class ConnectionProxy
    include ReplicaPools::QueryCache

    attr_accessor :leader
    attr_accessor :current, :current_pool, :replica_pools

    class << self
      def generate_safe_delegations
        ReplicaPools.config.safe_methods.each do |method|
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

    def initialize(leader, pools)
      @leader       = leader
      @replica_pools  = pools
      @current_pool = default_pool

      if ReplicaPools.config.defaults_to_leader
        @current = leader
      else
        @current = current_replica
      end

      # this ivar is for ConnectionAdapter compatibility
      # some gems (e.g. newrelic_rpm) will actually use
      # instance_variable_get(:@config) to find it.
      @config = current.connection_config
    end

    def with_pool(pool_name = 'default')
      last_conn, last_pool = self.current, self.current_pool
      self.current_pool = replica_pools[pool_name.to_sym] || default_pool
      self.current = current_replica
      yield
    ensure
      self.current_pool = last_pool
      self.current      = last_conn
    end

    def with_leader
      last_conn = self.current
      self.current = leader
      yield
    ensure
      self.current = last_conn
    end

    def transaction(*args, &block)
      with_leader { leader.transaction(*args, &block) }
    end

    def next_replica!
      self.current = current_pool.next
    end

    def current_replica
      current_pool.current
    end

    protected

    def default_pool
      replica_pools[:default] || replica_pools.values.first
    end

    # Proxies any unknown methods to leader.
    # Safe methods have been generated during `setup!`.
    # Creates a method to speed up subsequent calls.
    def method_missing(method, *args, &block)
      generate_unsafe_delegation(method)
      send(method, *args, &block)
    end

    def generate_unsafe_delegation(method)
      self.class_eval <<-END, __FILE__, __LINE__ + 1
        def #{method}(*args, &block)
          route_to(leader, :#{method}, *args, &block)
        end
      END
    end

    def route_to(conn, method, *args, &block)
      conn.retrieve_connection.send(method, *args, &block)
    rescue => e
      ReplicaPools.log :error, "Error during ##{method}: #{e}"
      log_proxy_state

      current.retrieve_connection.verify! # may reconnect
      raise e
    end

    private

    def log_proxy_state
      ReplicaPools.log :error, "Current Connection: #{current}"
      ReplicaPools.log :error, "Current Pool Name: #{current_pool.name}"
      ReplicaPools.log :error, "Current Pool Members: #{current_pool.replicas}"
    end
  end
end
