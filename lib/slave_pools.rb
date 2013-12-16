require 'active_record'
require 'slave_pools/config'
require 'slave_pools/pool'
require 'slave_pools/pools'
require 'slave_pools/active_record_extensions'
require 'slave_pools/hijack'
require 'slave_pools/observer_extensions'
require 'slave_pools/query_cache_compat'
require 'slave_pools/connection_proxy'

require 'slave_pools/engine' if defined? Rails
ActiveRecord::Observer.send :include, SlavePools::ObserverExtensions

module SlavePools
  class << self
    def setup!
      SlavePools::ConnectionProxy.setup!
    end

    def proxy
      ActiveRecord::Base.connection_proxy if active?
    end

    def active?
      ActiveRecord::Base.respond_to?('connection_proxy')
    end

    def next_slave!
      proxy.try(:next_slave!)
    end

    def with_pool(pool_name = 'default')
      if active?
        proxy.with_pool(pool_name) { yield }
      else
        yield
      end
    end

    def with_master
      if active?
        proxy.with_master { yield }
      else
        yield
      end
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
      @pools ||= SlavePools::Pools.new
    end
  end
end
