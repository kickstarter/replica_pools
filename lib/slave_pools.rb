require 'slave_pools/slave_pool'
require 'slave_pools/active_record_extensions'
require 'slave_pools/observer_extensions'
require 'slave_pools/query_cache_compat'
require 'slave_pools/connection_proxy'

#wrapper class to make the calls more succinct

class SlavePools
  
  def self.setup!
    SlavePoolsModule::ConnectionProxy.setup!
  end
  
  def self.active?
    ActiveRecord::Base.respond_to?('connection_proxy')
  end
  
  def self.next_slave!
    ActiveRecord::Base.connection_proxy.next_slave! if active?
  end
  
  def self.with_pool(pool_name = 'default')
    if active?
      ActiveRecord::Base.connection_proxy.with_pool(pool_name) { yield }
    else
      yield
    end
  end
  
  def self.with_master
    if active?
      ActiveRecord::Base.connection_proxy.with_master { yield }
    else
      yield
    end
  end

  def self.current
    ActiveRecord::Base.connection_proxy.current if active?
  end
end