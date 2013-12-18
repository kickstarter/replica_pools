module SlavePools
  module ActiveRecordExtensions
    def self.included(base)
      base.send :extend, ClassMethods
      base.cattr_accessor :connection_proxy
    end

    def reload(options = nil)
      self.connection_proxy.with_master { super }
    end

    module ClassMethods
      # Make sure transactions run on master
      # Even if they're initiated from ActiveRecord::Base
      # (which doesn't have our hijack).
      def transaction(options = {}, &block)
        if self.connection.kind_of?(ConnectionProxy)
          super
        else
          self.connection_proxy.with_master { super }
        end
      end
    end
  end
end
