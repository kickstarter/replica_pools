require_relative 'spec_helper'

describe ReplicaPools::Pool do

  context "Multiple replicas" do
    before do
      @replicas = ["db1", "db2", "db3"]
      @replica_pool = ReplicaPools::Pool.new("name", @replicas.clone)
    end

    specify { expect(@replica_pool.size).to(eq(3)) }

    it "should return items in a round robin fashion" do
      expect(@replica_pool.current).to(eq(@replicas[0]))
      expect(@replica_pool.next).to(eq(@replicas[1]))
      expect(@replica_pool.next).to(eq(@replicas[2]))
      expect(@replica_pool.next).to(eq(@replicas[0]))
    end
  end

  context "Single replica" do
    before do
      @replicas = ["db1"]
      @replica_pool = ReplicaPools::Pool.new("name", @replicas.clone)
    end

    specify { expect(@replica_pool.size).to(eq(1)) }

    it "should return items in a round robin fashion" do
      expect(@replica_pool.current).to(eq(@replicas[0]))
      expect(@replica_pool.next).to(eq(@replicas[0]))
    end
  end
end

