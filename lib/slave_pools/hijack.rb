module SlavePools
  module Hijack
    def self.extended(base)
      # hijack models that have already been loaded
      base.send(:descendants).each do |child|
        child.hijack_connection
      end
    end

    # hijack models that get loaded later
    def inherited(child)
      super
      child.hijack_connection
    end

    def hijack_connection
      class << self
        alias_method :connection, :connection_proxy
      end
    end
  end
end
