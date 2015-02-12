require_relative 'spec_helper'

describe ReplicaPools::Pool do

  context "Multiple replicas" do
    before do
      @replicas = ["db1", "db2", "db3"]
      @replica_pool = ReplicaPools::Pool.new("name", @replicas.clone)
    end

    specify {@replica_pool.size.should == 3}

    it "should return items in a round robin fashion" do
      @replica_pool.current.should == @replicas[0]
      @replica_pool.next.should == @replicas[1]
      @replica_pool.next.should == @replicas[2]
      @replica_pool.next.should == @replicas[0]
    end
  end

  context "Single replica" do
    before do
      @replicas = ["db1"]
      @replica_pool = ReplicaPools::Pool.new("name", @replicas.clone)
    end

    specify {@replica_pool.size.should == 1}

    it "should return items in a round robin fashion" do
      @replica_pool.current.should == @replicas[0]
      @replica_pool.next.should == @replicas[0]
    end
  end
end

