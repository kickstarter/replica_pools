module ReplicaPools
  class Pool
    attr_reader :name, :replicas, :current, :size

    def initialize(name, connections)
      @name      = name
      @replicas  = connections
      @size      = connections.size
      self.reset
    end

    def reset
      @cycle   = replicas.cycle
      self.next
    end

    def next
      @current = @cycle.next
    end
  end
end
