module SlavePoolsModule
  # Implements the methods expected by the QueryCache module
  module QueryCacheCompat

    def select_all(*a, &b)
      arel, name, binds = a
      if query_cache_enabled && !locked?(arel)
        # FIXME this still hits the +select_all+ method in AR connection's
        # query_cache.rb. It'd be nice if we could avoid it somehow so
        # +select_all+ and then +to_sql+ aren't called redundantly.
        sql = to_sql(arel, binds)
        @master.connection.send(:cache_sql, sql, binds) {send_to_current(:select_all, *[sql, name, binds], &b)}
      else
        send_to_current(:select_all, *a, &b)
      end
    end

    def insert(*a, &b)
      @master.connection.clear_query_cache if query_cache_enabled
      send_to_master(:insert, *a, &b)
    end

    def update(*a, &b)
      @master.connection.clear_query_cache if query_cache_enabled
      send_to_master(:update, *a, &b)
    end

    def delete(*a, &b)
      @master.connection.clear_query_cache if query_cache_enabled
      send_to_master(:delete, *a, &b)
    end

    # Rails 3.2 changed query cacheing a little and affected slave_pools like this:
    #
    #   * ActiveRecord::Base.cache sets @query_cache_enabled for current connection
    #   * ActiveRecord::QueryCache middleware (in call()) that Rails uses sets
    #     @query_cache_enabled directly on ActiveRecord::Base.connection
    #     (which could be master at that point)
    #
    # :`( So, let's just use the master connection for all query cacheing.
    def query_cache_enabled
      @master.connection.query_cache_enabled
    end
  end
end
