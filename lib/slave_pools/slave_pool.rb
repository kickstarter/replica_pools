module SlavePoolsModule
  class SlavePool
    # extend ThreadLocalAccessors
    
    attr_accessor :name, :slaves,:pool_size, :current_index
    #tlattr_accessor :current_index, true
    
    def initialize(name, slaves)
      @name = name
      @slaves = slaves
      @pool_size = @slaves.length
      # self.current_index = 0 
      @current_index = 0
    end
    
    def current
      # @slaves[self.current_index]
      @slaves[@current_index]
    end
    
    def next
      next_index! if @pool_size != 1
      current
    end
    
    protected
    
    def next_index!
      # self.current_index = (self.current_index + 1) % @pool_size
      @current_index = (@current_index + 1) % @pool_size
    end    

  end
end