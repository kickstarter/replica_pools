require 'delegate'

module ReplicaPools
  class Pools < ::SimpleDelegator
    include Enumerable

    def initialize
      pools = {}
      pool_configurations.group_by{ |_, name, _| name }.each do |name, set|
        pools[name.to_sym] = ReplicaPools::Pool.new(
          name,
          set.map do |conn_name, _, replica_name|
            connection_class(name, replica_name, conn_name)
          end
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
      config_hash.map do |name, config|
        next unless name.to_s =~ /#{ReplicaPools.config.environment}_pool_(.*)_name_(.*)/
        [name, $1, $2]
      end.compact
    end

    def config_hash
      if ActiveRecord::VERSION::MAJOR < 6
        # in Rails < 6, it's just a hash
        return ActiveRecord::Base.configurations
      end

      if ActiveRecord::VERSION::MAJOR == 6 && ActiveRecord::VERSION::MINOR < 1
        # in Rails = 6.0, `configurations` is an instance of ActiveRecord::DatabaseConfigurations
        return ActiveRecord::Base.configurations.to_h
      end

      # in Rails >= 6.1, ActiveRecord::Base.configurations.to_h has been deprecated
      ActiveRecord::Base.configurations.configs_for.map do |c|
        [c.env_name, c.configuration_hash.transform_keys(&:to_s)]
      end.to_h
    end

    # generates a unique ActiveRecord::Base subclass for a single replica
    def connection_class(pool_name, replica_name, connection_name)
      class_name = "#{pool_name.camelize}#{replica_name.camelize}"
      connection_config_method_name = ReplicaPools::ConnectionProxy.get_connection_config_method_name
      ReplicaPools.const_set(class_name, Class.new(ActiveRecord::Base) do |c|
        c.abstract_class = true
        c.define_singleton_method(connection_config_method_name) do
          if ActiveRecord::VERSION::MAJOR == 6
            configurations.configs_for(env_name: connection_name.to_s, include_replicas: true)
          elsif ActiveRecord::VERSION::MAJOR == 7
            configurations.configs_for(env_name: connection_name.to_s, include_hidden: true)
          end
        end
      end)

      ReplicaPools.const_get(class_name).tap do |c|
        c.establish_connection(connection_name.to_sym)
      end
    end

  end
end
