module ReplicaPools
  # duck-types with ActiveRecord::ConnectionAdapters::QueryCache
  # but relies on ActiveRecord::Base.query_cache for state so we
  # don't fragment the cache across multiple connections
  #
  # we could use more of ActiveRecord's QueryCache if it only
  # used accessors for its internal ivars.
  module QueryCache
    query_cache_methods = ActiveRecord::ConnectionAdapters::QueryCache.instance_methods(false)

    # these methods can all use the leader connection
    (query_cache_methods - [:select_all]).each do |method_name|
      define_method(method_name) do |*args, &block|
        ActiveRecord::Base.connection.send(method_name, *args, &block)
      end
    end

    # select_all is trickier. it needs to use the leader
    # connection for cache logic, but ultimately pass its query
    # through to whatever connection is current.
    def select_all(*args)
      relation, name, raw_binds = args

      if !query_cache_enabled || locked?(relation)
        return route_to(current, :select_all, *args)
      end

      # duplicate binds_from_relation behavior introduced in 4.2.
      if raw_binds.blank? && relation.is_a?(ActiveRecord::Relation)
        arel, binds = relation.arel, relation.bind_values
      else
        arel, binds = relation, Array(raw_binds)
      end

      sql = to_sql(arel, binds)

      args[0] = sql
      args[2] = binds

      if Gem::Version.new(ActiveRecord.version) < Gem::Version.new('5.1')
        cache_sql(sql, binds) { route_to(current, :select_all, *args) }
      else
        cache_sql(sql, name, binds) { route_to(current, :select_all, *args) }
      end
    end

    # If arel is locked this is a SELECT ... FOR UPDATE or somesuch. Such
    # queries should not be cached.
    def locked?(arel)
      # This method was copied from Rails 6.1, since it has been removed in 7.0
      arel = arel.arel if arel.is_a?(ActiveRecord::Relation)
      arel.respond_to?(:locked) && arel.locked
    end

    # these can use the unsafe delegation built into ConnectionProxy
    # [:insert, :update, :delete]
  end
end
