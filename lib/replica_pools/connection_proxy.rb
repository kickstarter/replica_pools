require 'active_record/connection_adapters/abstract/query_cache'
require 'set'

module ReplicaPools
  class ConnectionProxy
    include ReplicaPools::QueryCache

    attr_accessor :leader
    attr_accessor :leader_depth, :current, :current_pool, :replica_pools

    class << self
      def generate_safe_delegations
        ReplicaPools.config.safe_methods.each do |method|
          self.define_method(method) do |*args, &block|
            route_to(current, method, *args, &block)
          end unless instance_methods.include?(method)
        end
      end
    end

    def initialize(leader, pools)
      @leader        = leader
      @replica_pools = pools
      @leader_depth  = 0
      @current_pool  = default_pool

      if ReplicaPools.config.defaults_to_leader
        @current = leader
      else
        @current = current_replica
      end

      # this ivar is for ConnectionAdapter compatibility
      # some gems (e.g. newrelic_rpm) will actually use
      # instance_variable_get(:@config) to find it.
      @config = current.send(ReplicaPools::ConnectionProxy.get_connection_config_method_name)
    end

    def self.get_connection_config_method_name
      # 6.1 supports current.connection_config
      # but warns of impending deprecation in 6.2
      if ActiveRecord::VERSION::STRING.to_f >= 6.1
        :connection_db_config
      else
        :connection_config
      end
    end

    def with_pool(pool_name = 'default')
      last_conn, last_pool = self.current, self.current_pool
      self.current_pool = replica_pools[pool_name.to_sym] || default_pool
      self.current = current_replica unless within_leader_block?
      yield
    ensure
      self.current_pool = last_pool
      self.current      = last_conn
    end

    def with_leader
      raise LeaderDisabled.new if ReplicaPools.config.disable_leader

      last_conn = self.current
      self.current = leader
      self.leader_depth += 1
      yield
    ensure
      if last_conn
        self.leader_depth = [leader_depth - 1, 0].max
        self.current = last_conn
      end
    end

    def transaction(...)
      with_leader { leader.transaction(...) }
    end

    def next_replica!
      return if within_leader_block?
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
    def method_missing(method, *args, **kwargs, &block)
      self.class.define_method(method) do |*args, **kwargs, &block|
        route_to(leader, method, *args, **kwargs, &block).tap do
          if %i[insert delete update].include?(method)
            leader.retrieve_connection.clear_query_cache
          end
        end
      end
      send(method, *args, &block)
    end

    def within_leader_block?
      leader_depth > 0
    end

    def route_to(conn, method, *args, **keyword_args, &block)
      raise ReplicaPools::LeaderDisabled.new if ReplicaPools.config.disable_leader && conn == leader
      conn.retrieve_connection.send(method, *args, **keyword_args, &block)
    rescue => e
      ReplicaPools.log :error, "Error during ##{method}: #{e}"
      log_proxy_state
      raise e
    end

    private

    def log_proxy_state
      ReplicaPools.log :error, "Current Connection: #{current}"
      ReplicaPools.log :error, "Current Pool Name: #{current_pool.name}"
      ReplicaPools.log :error, "Current Pool Members: #{current_pool.replicas}"
      ReplicaPools.log :error, "Leader Depth: #{leader_depth}"
    end
  end
end
