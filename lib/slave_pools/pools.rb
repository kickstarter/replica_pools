require 'delegate'

module SlavePools
  class Pools < ::SimpleDelegator
    include Enumerable

    def initialize
      # group the pools by name
      pools = Hash.new{|h, k| h[k] = [] }
      slave_pool_configurations.each do |conn_name, pool_name, slave_name|
        pools[pool_name] << connection_class(pool_name, slave_name, conn_name)
      end

      # typecast
      pools = pools.keys.inject({}) do |h, name|
        h.merge! name.to_sym => SlavePools::Pool.new(name, pools[name])
      end

      super pools
    end

    private

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
  end
end
