require_relative 'spec_helper'
require_relative 'config/test_model'

describe ReplicaPools do

  before(:each) do
    @sql = 'SELECT NOW()'

    @proxy = ReplicaPools.proxy
    @leader = @proxy.leader.retrieve_connection

    reset_proxy(@proxy)
    create_replica_aliases(@proxy)
  end

  it 'AR::B should respond to #connection_proxy' do
    ActiveRecord::Base.should respond_to(:connection_proxy)
    ActiveRecord::Base.connection_proxy.should be_kind_of(ReplicaPools::ConnectionProxy)
  end

  it 'TestModel#connection should return an instance of ReplicaPools::ConnectionProxy' do
    TestModel.connection.should be_kind_of(ReplicaPools::ConnectionProxy)
  end

  it "should generate classes for each entry in the database.yml" do
    defined?(ReplicaPools::DefaultDb1).should_not be_nil
    defined?(ReplicaPools::DefaultDb2).should_not be_nil
    defined?(ReplicaPools::SecondaryDb1).should_not be_nil
    defined?(ReplicaPools::SecondaryDb2).should_not be_nil
    defined?(ReplicaPools::SecondaryDb3).should_not be_nil
  end

  context "with_leader" do
    it 'should revert to previous replica connection' do
      @proxy.current = @proxy.current_replica
      @proxy.with_leader do
        @proxy.current.should equal(@proxy.leader)
      end
      @proxy.current.name.should eq('ReplicaPools::DefaultDb1')
    end

    it 'should revert to previous leader connection' do
      @proxy.current = @proxy.leader
      @proxy.with_leader do
        @proxy.current.should equal(@proxy.leader)
      end
      @proxy.current.should equal(@proxy.leader)
    end

    it 'should know when in block' do
      @proxy.send(:within_leader_block?).should_not be
      @proxy.with_leader do
        @proxy.send(:within_leader_block?).should be
      end
      @proxy.send(:within_leader_block?).should_not be
    end
  end

  context "transaction" do
    it 'should send all to leader' do
      @leader.should_receive(:select_all).exactly(1)
      @default_replica1.should_receive(:select_all).exactly(0)

      TestModel.transaction do
        @proxy.select_all(@sql)
      end
    end

    it 'should send all to leader even if transactions begins on AR::Base' do
      @leader.should_receive(:select_all).exactly(1)
      @default_replica1.should_receive(:select_all).exactly(0)

      ActiveRecord::Base.transaction do
        @proxy.select_all(@sql)
      end
    end
  end

  it 'should perform transactions on the leader, and selects outside of transaction on the replica' do
    @default_replica1.should_receive(:select_all).exactly(2) # before and after the transaction go to replicas
    @leader.should_receive(:select_all).exactly(5)
    @proxy.select_all(@sql)
    ActiveRecord::Base.transaction do
      5.times {@proxy.select_all(@sql)}
    end
    @proxy.select_all(@sql)
  end

  it 'should not switch replicas automatically on selects' do
    @default_replica1.should_receive(:select_one).exactly(6)
    @default_replica2.should_receive(:select_one).exactly(0)
    6.times { @proxy.select_one(@sql) }
  end

  context "next_replica!" do
    it 'should switch to the next replica' do
      @default_replica1.should_receive(:select_one).exactly(1)
      @default_replica2.should_receive(:select_one).exactly(1)

      @proxy.select_one(@sql)
      @proxy.next_replica!
      @proxy.select_one(@sql)
    end

    it 'should not switch when in a with_leader-block' do
      @leader.should_receive(:select_one).exactly(2)
      @default_replica1.should_not_receive(:select_one)
      @default_replica2.should_not_receive(:select_one)

      @proxy.with_leader do
        @proxy.select_one(@sql)
        @proxy.next_replica!
        @proxy.select_one(@sql)
      end
    end
  end

  it 'should send dangerous methods to the leader' do
    meths = [:insert, :update, :delete, :execute]
    meths.each do |meth|
      @default_replica1.stub(meth).and_raise(RuntimeError)
      @leader.should_receive(meth).and_return(true)
      @proxy.send(meth, @sql)
    end
  end

  it "should not allow leader depth to get below 0" do
    @proxy.instance_variable_set("@leader_depth", -500)
    @proxy.instance_variable_get("@leader_depth").should == -500
    @proxy.with_leader {@sql}
    @proxy.instance_variable_get("@leader_depth").should == 0
  end

  it 'should pre-generate safe methods' do
    @proxy.should respond_to(:select_value)
  end

  it 'should dynamically generate unsafe methods' do
    @leader.should_receive(:unsafe).and_return(true)

    @proxy.should_not respond_to(:unsafe)
    @proxy.unsafe(@sql)
    @proxy.should respond_to(:unsafe)
  end

  it 'should not replay errors on leader' do
    @default_replica1.should_receive(:select_all).once.and_raise(ArgumentError.new('random message'))
    @default_replica2.should_not_receive(:select_all)
    @leader.should_not_receive(:select_all)
    lambda { @proxy.select_all(@sql) }.should raise_error(ArgumentError)
  end

  it 'should reload models from the leader' do
    foo = TestModel.create!
    @leader.should_receive(:select_all).and_return(ActiveRecord::Result.new(["id"], ["1"]))
    @default_replica1.should_not_receive(:select_all)
    @default_replica2.should_not_receive(:select_all)
    foo.reload
  end

  context "with_pool" do

    it "should switch to the named pool" do
      @proxy.with_pool('secondary') do
        @proxy.current_pool.name.should eq('secondary')
        @proxy.current.name.should eq('ReplicaPools::SecondaryDb1')
      end
    end

    it "should switch to default pool if an unknown pool is specified" do
      @proxy.with_pool('unknown') do
        @proxy.current_pool.name.should eq('default')
        @proxy.current.name.should eq('ReplicaPools::DefaultDb1')
      end
    end

    it "should switch to default pool if no pool is specified" do
      @proxy.with_pool do
        @proxy.current_pool.name.should eq('default')
        @proxy.current.name.should eq('ReplicaPools::DefaultDb1')
      end
    end

    it "should cycle replicas only within the pool" do
      @proxy.with_pool('secondary') do
        @proxy.current.name.should eq('ReplicaPools::SecondaryDb1')
        @proxy.next_replica!
        @proxy.current.name.should eq('ReplicaPools::SecondaryDb2')
        @proxy.next_replica!
        @proxy.current.name.should eq('ReplicaPools::SecondaryDb3')
        @proxy.next_replica!
        @proxy.current.name.should eq('ReplicaPools::SecondaryDb1')
      end
    end

    it "should allow switching back to leader" do
      @proxy.with_pool('secondary') do
        @proxy.current.name.should eq('ReplicaPools::SecondaryDb1')
        @proxy.with_leader do
          @proxy.current.name.should eq('ActiveRecord::Base')
        end
      end
    end

    it "should not switch to pool when nested inside with_leader" do
      @proxy.current.name.should eq('ReplicaPools::DefaultDb1')
      @proxy.with_leader do
        @proxy.with_pool('secondary') do
          @proxy.current.name.should eq('ActiveRecord::Base')
        end
      end
    end

    it "should switch back to previous pool and replica" do
      @proxy.next_replica!

      @proxy.current_pool.name.should eq('default')
      @proxy.current.name.should eq('ReplicaPools::DefaultDb2')

      @proxy.with_pool('secondary') do
        @proxy.current_pool.name.should eq('secondary')
        @proxy.current.name.should eq('ReplicaPools::SecondaryDb1')

        @proxy.with_pool('default') do
          @proxy.current_pool.name.should eq('default')
          @proxy.current.name.should eq('ReplicaPools::DefaultDb2')
        end

        @proxy.current_pool.name.should eq('secondary')
        @proxy.current.name.should eq('ReplicaPools::SecondaryDb1')
      end

      @proxy.current_pool.name.should eq('default')
      @proxy.current.name.should eq('ReplicaPools::DefaultDb2')
    end
  end
end

