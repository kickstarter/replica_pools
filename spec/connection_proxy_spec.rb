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
    expect(ActiveRecord::Base).to(respond_to(:connection_proxy))
    expect(ActiveRecord::Base.connection_proxy).to(be_kind_of(ReplicaPools::ConnectionProxy))
  end

  it 'TestModel#connection should return an instance of ReplicaPools::ConnectionProxy' do
    expect(TestModel.connection).to(be_kind_of(ReplicaPools::ConnectionProxy))
  end

  it "should generate classes for each entry in the database.yml" do
    expect(defined?(ReplicaPools::DefaultDb1)).to_not(be_nil)
    expect(defined?(ReplicaPools::DefaultDb2)).to_not(be_nil)
    expect(defined?(ReplicaPools::SecondaryDb1)).to_not(be_nil)
    expect(defined?(ReplicaPools::SecondaryDb2)).to_not(be_nil)
    expect(defined?(ReplicaPools::SecondaryDb3)).to_not(be_nil)
  end

  context "with_leader" do
    it 'should revert to previous replica connection' do
      @proxy.current = @proxy.current_replica
      @proxy.with_leader do
        expect(@proxy.current).to(equal(@proxy.leader))
      end
      expect(@proxy.current.name).to(eq('ReplicaPools::DefaultDb1'))
    end

    it 'should revert to previous leader connection' do
      @proxy.current = @proxy.leader
      @proxy.with_leader do
        expect(@proxy.current).to(equal(@proxy.leader))
      end
      expect(@proxy.current).to(equal(@proxy.leader))
    end

    it 'should know when in block' do
      expect(@proxy.send(:within_leader_block?)).to_not(be)
      @proxy.with_leader do
        expect(@proxy.send(:within_leader_block?)).to(be)
      end
      expect(@proxy.send(:within_leader_block?)).to_not(be)
    end
  end

  context "transaction" do
    it 'should send all to leader' do
      expect(@leader).to(receive(:select_all).exactly(1))
      expect(@default_replica1).to(receive(:select_all).exactly(0))

      TestModel.transaction do
        @proxy.select_all(@sql)
      end
    end

    it 'should send all to leader even if transactions begins on AR::Base' do
      expect(@leader).to(receive(:select_all).exactly(1))
      expect(@default_replica1).to(receive(:select_all).exactly(0))

      ActiveRecord::Base.transaction do
        @proxy.select_all(@sql)
      end
    end
  end

  it 'should perform transactions on the leader, and selects outside of transaction on the replica' do
    expect(@default_replica1).to(receive(:select_all).exactly(2)) # before and after the transaction go to replicas
    expect(@leader).to(receive(:select_all).exactly(5))
    @proxy.select_all(@sql)
    ActiveRecord::Base.transaction do
      5.times {@proxy.select_all(@sql)}
    end
    @proxy.select_all(@sql)
  end

  it 'should not switch replicas automatically on selects' do
    expect(@default_replica1).to(receive(:select_one).exactly(6))
    expect(@default_replica2).to(receive(:select_one).exactly(0))
    6.times { @proxy.select_one(@sql) }
  end

  context "next_replica!" do
    it 'should switch to the next replica' do
      expect(@default_replica1).to(receive(:select_one).exactly(1))
      expect(@default_replica2).to(receive(:select_one).exactly(1))

      @proxy.select_one(@sql)
      @proxy.next_replica!
      @proxy.select_one(@sql)
    end

    it 'should not switch when in a with_leader-block' do
      expect(@leader).to(receive(:select_one).exactly(2))
      expect(@default_replica1).to_not(receive(:select_one))
      expect(@default_replica2).to_not(receive(:select_one))

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
      expect(@default_replica1).to(receive(meth)).never
      expect(@leader).to(receive(meth).and_return(true))
      @proxy.send(meth, @sql)
    end
  end

  it "should not allow leader depth to get below 0" do
    @proxy.instance_variable_set("@leader_depth", -500)
    expect(@proxy.instance_variable_get("@leader_depth")).to(eq(-500))
    @proxy.with_leader {@sql}
    expect(@proxy.instance_variable_get("@leader_depth")).to(eq(0))
  end

  it 'should pre-generate safe methods' do
    expect(@proxy).to(respond_to(:select_value))
  end

  it 'should dynamically generate unsafe methods' do
    expect(@leader).to(receive(:unsafe).and_return(true))

    expect(@proxy).to_not(respond_to(:unsafe))
    @proxy.unsafe(@sql)
    expect(@proxy).to(respond_to(:unsafe))
  end

  it 'should not replay errors on leader' do
    expect(@default_replica1).to(receive(:select_all).once.and_raise(ArgumentError.new('random message')))
    expect(@default_replica2).to_not(receive(:select_all))
    expect(@leader).to_not(receive(:select_all))
    expect(lambda { @proxy.select_all(@sql) }).to(raise_error(ArgumentError))
  end

  it 'should reload models from the leader' do
    foo = TestModel.create!
    expect(@leader).to(receive(:select_all).and_return(ActiveRecord::Result.new(["id"], ["1"])))
    expect(@default_replica1).to_not(receive(:select_all))
    expect(@default_replica2).to_not(receive(:select_all))
    foo.reload
  end

  context "with_pool" do

    it "should switch to the named pool" do
      @proxy.with_pool('secondary') do
        expect(@proxy.current_pool.name).to(eq('secondary'))
        expect(@proxy.current.name).to(eq('ReplicaPools::SecondaryDb1'))
      end
    end

    it "should switch to default pool if an unknown pool is specified" do
      @proxy.with_pool('unknown') do
        expect(@proxy.current_pool.name).to(eq('default'))
        expect(@proxy.current.name).to(eq('ReplicaPools::DefaultDb1'))
      end
    end

    it "should switch to default pool if no pool is specified" do
      @proxy.with_pool do
        expect(@proxy.current_pool.name).to(eq('default'))
        expect(@proxy.current.name).to(eq('ReplicaPools::DefaultDb1'))
      end
    end

    it "should cycle replicas only within the pool" do
      @proxy.with_pool('secondary') do
        expect(@proxy.current.name).to(eq('ReplicaPools::SecondaryDb1'))
        @proxy.next_replica!
        expect(@proxy.current.name).to(eq('ReplicaPools::SecondaryDb2'))
        @proxy.next_replica!
        expect(@proxy.current.name).to(eq('ReplicaPools::SecondaryDb3'))
        @proxy.next_replica!
        expect(@proxy.current.name).to(eq('ReplicaPools::SecondaryDb1'))
      end
    end

    it "should allow switching back to leader" do
      @proxy.with_pool('secondary') do
        expect(@proxy.current.name).to(eq('ReplicaPools::SecondaryDb1'))
        @proxy.with_leader do
          expect(@proxy.current.name).to(eq('ActiveRecord::Base'))
        end
      end
    end

    it "should not switch to pool when nested inside with_leader" do
      expect(@proxy.current.name).to(eq('ReplicaPools::DefaultDb1'))
      @proxy.with_leader do
        @proxy.with_pool('secondary') do
          expect(@proxy.current.name).to(eq('ActiveRecord::Base'))
        end
      end
    end

    it "should switch back to previous pool and replica" do
      @proxy.next_replica!

      expect(@proxy.current_pool.name).to(eq('default'))
      expect(@proxy.current.name).to(eq('ReplicaPools::DefaultDb2'))

      @proxy.with_pool('secondary') do
        expect(@proxy.current_pool.name).to(eq('secondary'))
        expect(@proxy.current.name).to(eq('ReplicaPools::SecondaryDb1'))

        @proxy.with_pool('default') do
          expect(@proxy.current_pool.name).to(eq('default'))
          expect(@proxy.current.name).to(eq('ReplicaPools::DefaultDb2'))
        end

        expect(@proxy.current_pool.name).to(eq('secondary'))
        expect(@proxy.current.name).to(eq('ReplicaPools::SecondaryDb1'))
      end

      expect(@proxy.current_pool.name).to(eq('default'))
      expect(@proxy.current.name).to(eq('ReplicaPools::DefaultDb2'))
    end
  end
end

