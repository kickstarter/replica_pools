require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require SLAVE_POOLS_SPEC_DIR + '/../lib/slave_pools'

describe SlavePoolsModule::SlavePool do
  
  context "Multiple slaves" do
    before do
      @slaves = ["db1", "db2", "db3"]
      @slave_pool = SlavePoolsModule::SlavePool.new("name", @slaves.clone)
    end
    specify {@slave_pool.pool_size.should == 3}

    it "should return items in a round robin fashion" do
      first = @slaves.shift
      @slave_pool.current.should == first
      @slaves.each do |item|
        @slave_pool.next.should == item
      end
      @slave_pool.next.should == first
    end
  end
  
  context "Single Slave" do
    before do
      @slaves = ["db1"]
      @slave_pool = SlavePoolsModule::SlavePool.new("name", @slaves.clone)
    end
    specify {@slave_pool.pool_size.should == 1}

    it "should return items in a round robin fashion" do
      @slave_pool.current.should == "db1"
      @slave_pool.next.should == "db1"
      @slave_pool.next.should == "db1"
    end
    
    it "shouldn't call next_reader! if there is only one slave" do
      @slave_pool.should_not_receive(:next_index!)
      @slave_pool.current.should == "db1"
      @slave_pool.next.should == "db1"
      @slave_pool.next.should == "db1"
    end
  end  
end

