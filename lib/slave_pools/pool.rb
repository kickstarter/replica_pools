module SlavePools
  class Pool
    attr_reader :name, :slaves, :current, :size

    def initialize(name, connections)
      @name    = name
      @slaves  = connections
      @size    = connections.size
      self.reset
    end

    def reset
      @cycle   = slaves.cycle
      self.next
    end

    def next
      @current = @cycle.next
    end
  end
end
