require 'active_record'
require 'slave_pools/config'
require 'slave_pools/pool'
require 'slave_pools/pools'
require 'slave_pools/active_record_extensions'
require 'slave_pools/hijack'
require 'slave_pools/query_cache'
require 'slave_pools/connection_proxy'

require 'slave_pools/engine' if defined? Rails
ActiveRecord::Base.send :include, SlavePools::ActiveRecordExtensions

module SlavePools
  class << self

    def config
      @config ||= SlavePools::Config.new
    end

    def setup!
      ConnectionProxy.generate_safe_delegations

      ActiveRecord::Base.send(:extend, SlavePools::Hijack)

      log :info, "Proxy loaded with: #{pools.keys.join(', ')}"
    end

    def proxy
      Thread.current[:slave_pools_proxy] ||= SlavePools::ConnectionProxy.new(
        ActiveRecord::Base,
        SlavePools.pools
      )
    end

    def current
      proxy.current
    end

    def next_slave!
      proxy.next_slave!
    end

    def with_pool(*a)
      proxy.with_pool(*a){ yield }
    end

    def with_master
      proxy.with_master{ yield }
    end

    def pools
      Thread.current[:slave_pools] ||= SlavePools::Pools.new
    end

    def log(level, message)
      logger.send(level, "[SlavePools] #{message}")
    end

    def logger
      ActiveRecord::Base.logger
    end
  end
end
