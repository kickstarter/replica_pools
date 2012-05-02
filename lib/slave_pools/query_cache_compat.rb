module SlavePoolsModule
  # Implements the methods expected by the QueryCache module
  module QueryCacheCompat

    def select_all(*a, &b)
      if @query_cache_enabled
        # FIXME this will still hit the +select_all+ method in AR's 
        # query_cache.rb. It'd be nice if we could avoid it somehow so 
        # +select_all+ and then +to_sql+ aren't called redundantly.
        arel, name, binds = a
        sql = to_sql(arel, binds)
        cache_sql(sql, binds) {send_to_current(:select_all, *[sql, name, binds], &b)}
      else
        send_to_current(:select_all, *a, &b)
      end
    end

    def columns(*a, &b)
      if @query_cache_enabled
        cache_sql(a.first, a.last) {send_to_current(:columns, *a, &b)}
      else
        send_to_current(:columns, *a, &b)
      end
    end
    
    def insert(*a, &b)
      clear_query_cache if @query_cache_enabled
      send_to_master(:insert, *a, &b)
    end
    
    def update(*a, &b)
      clear_query_cache if @query_cache_enabled
      send_to_master(:update, *a, &b)
    end
    
    def delete(*a, &b)
      clear_query_cache if @query_cache_enabled
      send_to_master(:delete, *a, &b)
    end
  end
end