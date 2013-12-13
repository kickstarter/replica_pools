require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe SlavePools::SlavePool do

  context "Multiple slaves" do
    before do
      @slaves = ["db1", "db2", "db3"]
      @slave_pool = SlavePools::SlavePool.new("name", @slaves.clone)
    end

    specify {@slave_pool.size.should == 3}

    it "should return items in a round robin fashion" do
      @slave_pool.current.should == @slaves[0]
      @slave_pool.next.should == @slaves[1]
      @slave_pool.next.should == @slaves[2]
      @slave_pool.next.should == @slaves[0]
    end
  end

  context "Single Slave" do
    before do
      @slaves = ["db1"]
      @slave_pool = SlavePools::SlavePool.new("name", @slaves.clone)
    end

    specify {@slave_pool.size.should == 1}

    it "should return items in a round robin fashion" do
      @slave_pool.current.should == @slaves[0]
      @slave_pool.next.should == @slaves[0]
    end
  end
end

