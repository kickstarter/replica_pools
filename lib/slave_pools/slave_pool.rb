module SlavePoolsModule
  class SlavePool
    
    attr_accessor :name, :slaves,:pool_size, :current_index
    
    def initialize(name, slaves)
      @name = name
      @slaves = slaves
      @pool_size = @slaves.length
      @current_index = 0
    end
    
    def current
      @slaves[@current_index]
    end
    
    def next
      next_index! if @pool_size != 1
      current
    end
    
    protected
    
    def next_index!
      @current_index = (@current_index + 1) % @pool_size
    end    

  end
end