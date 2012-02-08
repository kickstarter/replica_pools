module SlavePools
  module ActiveRecordExtensions
    def self.included(base)
      base.send :include, InstanceMethods
      base.send :extend, ClassMethods
      base.cattr_accessor :connection_proxy
      # handle subclasses which were defined by the framework or plugins
      base.send(:descendants).each do |child|
        child.hijack_connection
      end
    end

    module InstanceMethods
      def reload(options = nil)
        self.connection_proxy.with_master { super }
      end
    end

    module ClassMethods
      # Make sure transactions always switch to the master
      def transaction(&block)
        if self.connection.kind_of?(ConnectionProxy)
          super
        else
          self.connection_proxy.with_master { super }
        end
      end

      # make caching always use the ConnectionProxy
      def cache(&block)
        if ActiveRecord::Base.configurations.blank?
          yield
        else
          self.connection_proxy.cache(&block)
        end
      end

      def inherited(child)
        super
        child.hijack_connection
      end

      def hijack_connection
        return if ConnectionProxy.master_models.include?(self.to_s)
        logger.info "[SlavePools] hijacking connection for #{self.to_s}"
        class << self
          def connection
            self.connection_proxy
          end
        end
      end
      
      # #new method to verify whether DB connection is active?
      # def connection_valid?(db_config = nil)
      #   is_connected = false
      #   if db_config
      #     begin
      #       establish_connection(db_config)
      #       connection
      #       is_connected = self.connected?
      #       #remove_connection
      #     rescue
      #     end
      #   end
      #   return is_connected
      # end
      
    end
  end
end