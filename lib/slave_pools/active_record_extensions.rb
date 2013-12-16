module SlavePools
  module ActiveRecordExtensions
    def self.included(base)
      base.cattr_accessor :connection_proxy

      base.send :include, InstanceMethods
      base.send :extend, ClassMethods
    end

    module InstanceMethods
      def reload(options = nil)
        self.connection_proxy.with_master { super }
      end
    end

    module ClassMethods
      # Make sure transactions always switch to the master
      def transaction(options = {}, &block)
        if self.connection.kind_of?(ConnectionProxy)
          super
        else
          self.connection_proxy.with_master { super }
        end
      end

      # Make sure caching always uses master connection
      def cache(&block)
        if ActiveRecord::Base.configurations.blank?
          yield
        else
          ActiveRecord::Base.connection.cache(&block)
        end
      end
    end
  end
end
