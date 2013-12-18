require 'active_record'
require 'slave_pools/config'
require 'slave_pools/pool'
require 'slave_pools/pools'
require 'slave_pools/active_record_extensions'
require 'slave_pools/hijack'
require 'slave_pools/observer_extensions'
require 'slave_pools/query_cache'
require 'slave_pools/connection_proxy'

require 'slave_pools/engine' if defined? Rails
ActiveRecord::Observer.send :include, SlavePools::ObserverExtensions
ActiveRecord::Base.send :include, SlavePools::ActiveRecordExtensions

module SlavePools
  class << self
    def setup!
      if SlavePools.pools.empty?
        SlavePools.logger.info("[SlavePools] No pools found for #{SlavePools.config.environment}. Loading a default pool with master instead.")
        SlavePools.pools['default'] = SlavePools::Pool.new('default', [ActiveRecord::Base])
      end

      ConnectionProxy.generate_safe_delegations

      ActiveRecord::Base.send(:extend, SlavePools::Hijack)
      ActiveRecord::Base.connection_proxy = SlavePools.proxy

      SlavePools.logger.info("[SlavePools] Proxy loaded with: #{SlavePools.pools.keys.join(', ')}")
    end

    def proxy
      Thread.current[:slave_pools_proxy] ||= SlavePools::ConnectionProxy.new(
        ActiveRecord::Base,
        SlavePools.pools
      )
    end

    def next_slave!
      proxy.try(:next_slave!)
    end

    def with_pool(pool_name = 'default')
      proxy.with_pool(pool_name) { yield }
    end

    def with_master
      proxy.with_master { yield }
    end

    def current
      proxy.try(:current)
    end

    def logger
      ActiveRecord::Base.logger
    end

    def config
      @config ||= SlavePools::Config.new
    end

    def pools
      Thread.current[:slave_pools] ||= SlavePools::Pools.new
    end
  end
end
