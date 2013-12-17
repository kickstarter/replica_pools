module SlavePools
  class Pool
    attr_reader :name, :slaves, :current, :size

    def initialize(name, slaves)
      @name    = name
      @slaves  = slaves
      @size    = slaves.size
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
