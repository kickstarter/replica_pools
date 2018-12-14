require 'active_record'
require 'replica_pools/config'
require 'replica_pools/pool'
require 'replica_pools/pools'
require 'replica_pools/active_record_extensions'
require 'replica_pools/hijack'
require 'replica_pools/query_cache'
require 'replica_pools/connection_proxy'

require 'replica_pools/engine' if defined? Rails
ActiveRecord::Base.send :include, ReplicaPools::ActiveRecordExtensions

module ReplicaPools
  class LeaderDisabled < StandardError
    def to_s
      "Leader database has been disabled. Re-enable with ReplicaPools.config.disable_leader = false."
    end
  end

  class << self

    def config
      @config ||= ReplicaPools::Config.new
    end

    def setup!
      ConnectionProxy.generate_safe_delegations

      ActiveRecord::Base.send(:extend, ReplicaPools::Hijack)

      log :info, "Proxy loaded with: #{pools.keys.join(', ')}"
    end

    def proxy
      Thread.current[:replica_pools_proxy] ||= ReplicaPools::ConnectionProxy.new(
        ActiveRecord::Base,
        ReplicaPools.pools
      )
    end

    def current
      proxy.current
    end

    def next_replica!
      proxy.next_replica!
    end

    def with_pool(*a)
      proxy.with_pool(*a){ yield }
    end

    def with_leader
      raise LeaderDisabled.new if ReplicaPools.config.disable_leader
      proxy.with_leader{ yield }
    end

    def pools
      Thread.current[:replica_pools] ||= ReplicaPools::Pools.new
    end

    def log(level, message)
      logger.send(level, "[ReplicaPools] #{message}")
    end

    def logger
      ActiveRecord::Base.logger
    end
  end
end
