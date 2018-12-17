module ReplicaPools
  module ActiveRecordExtensions
    def self.included(base)
      base.send :extend, ClassMethods
    end

    def reload(options = nil)
      if ReplicaPools.config.disable_leader
        super
      else
        self.class.connection_proxy.with_leader { super }
      end
    end

    module ClassMethods
      def connection_proxy
        ReplicaPools.proxy
      end

      # Make sure transactions run on leader
      # Even if they're initiated from ActiveRecord::Base
      # (which doesn't have our hijack).
      def transaction(options = {}, &block)
        if self.connection.kind_of?(ConnectionProxy)
          super
        else
          self.connection_proxy.with_leader { super }
        end
      end
    end
  end
end
