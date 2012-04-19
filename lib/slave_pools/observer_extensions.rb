module SlavePoolsModule
  module ObserverExtensions
    def self.included(base)
      base.alias_method_chain :update, :masterdb
    end
    
    # Send observed_method(object) if the method exists.
    # currently replicating the update method instead of using the aliased method call to update_without_master
    def update_with_masterdb(observed_method, object, &block) #:nodoc:
      if object.class.connection.respond_to?(:with_master)
        object.class.connection.with_master do
          send(observed_method, object, &block) if respond_to?(observed_method) && !disabled_for?(object)
        end
      else
        send(observed_method, object, &block) if respond_to?(observed_method) && !disabled_for?(object)
      end
    end
  end
end