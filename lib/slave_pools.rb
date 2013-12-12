require 'active_record'
require 'slave_pools/slave_pool'
require 'slave_pools/active_record_extensions'
require 'slave_pools/observer_extensions'
require 'slave_pools/query_cache_compat'
require 'slave_pools/connection_proxy'

module SlavePools
  class << self
    def setup!
      SlavePools::ConnectionProxy.setup!
    end

    def active?
      ActiveRecord::Base.respond_to?('connection_proxy')
    end

    def next_slave!
      ActiveRecord::Base.connection_proxy.next_slave! if active?
    end

    def with_pool(pool_name = 'default')
      if active?
        ActiveRecord::Base.connection_proxy.with_pool(pool_name) { yield }
      else
        yield
      end
    end

    def with_master
      if active?
        ActiveRecord::Base.connection_proxy.with_master { yield }
      else
        yield
      end
    end

    def current
      ActiveRecord::Base.connection_proxy.current if active?
    end
  end
end
