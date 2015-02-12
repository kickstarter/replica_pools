require 'delegate'

module ReplicaPools
  class Pools < ::SimpleDelegator
    include Enumerable

    def initialize
      pools = {}
      pool_configurations.group_by{|_, name, _| name }.each do |name, set|
        pools[name.to_sym] = ReplicaPools::Pool.new(
          name,
          set.map{ |conn_name, _, replica_name|
            connection_class(name, replica_name, conn_name)
          }
        )
      end

      if pools.empty?
        ReplicaPools.log :info, "No pools found for #{ReplicaPools.config.environment}. Loading a default pool with leader instead."
        pools[:default] = ReplicaPools::Pool.new('default', [ActiveRecord::Base])
      end

      super pools
    end

    private

    # finds valid pool configs
    def pool_configurations
      ActiveRecord::Base.configurations.map do |name, config|
        next unless name.to_s =~ /#{ReplicaPools.config.environment}_pool_(.*)_name_(.*)/
        [name, $1, $2]
      end.compact
    end

    # generates a unique ActiveRecord::Base subclass for a single replica
    def connection_class(pool_name, replica_name, connection_name)
      class_name = "#{pool_name.camelize}#{replica_name.camelize}"

      ReplicaPools.module_eval %Q{
        class #{class_name} < ActiveRecord::Base
          self.abstract_class = true
          establish_connection :#{connection_name}
          def self.connection_config
            configurations[#{connection_name.to_s.inspect}]
          end
        end
      }, __FILE__, __LINE__
      ReplicaPools.const_get(class_name)
    end
  end
end
