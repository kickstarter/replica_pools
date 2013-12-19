require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe SlavePools do

  before(:each) do
    @sql = 'SELECT NOW()'

    @proxy = SlavePools.proxy
    @master = @proxy.master.retrieve_connection

    reset_proxy(@proxy)
    create_slave_aliases(@proxy)
  end

  it 'AR::B should respond to #connection_proxy' do
    ActiveRecord::Base.should respond_to(:connection_proxy)
    ActiveRecord::Base.connection_proxy.should be_kind_of(SlavePools::ConnectionProxy)
  end

  it 'TestModel#connection should return an instance of SlavePools::ConnectionProxy' do
    TestModel.connection.should be_kind_of(SlavePools::ConnectionProxy)
  end

  it "should generate classes for each entry in the database.yml" do
    defined?(SlavePools::DefaultDb1).should_not be_nil
    defined?(SlavePools::DefaultDb2).should_not be_nil
    defined?(SlavePools::SecondaryDb1).should_not be_nil
    defined?(SlavePools::SecondaryDb2).should_not be_nil
    defined?(SlavePools::SecondaryDb3).should_not be_nil
  end

  it "should not generate classes for an invalid DB in the database.yml" do
    defined?(SlavePools::DefaultFakeDb).should be_nil
  end

  context "with_master" do
    it 'should revert to previous slave connection' do
      @proxy.current = @proxy.current_slave
      @proxy.with_master do
        @proxy.current.should equal(@proxy.master)
      end
      @proxy.current.name.should eq('SlavePools::DefaultDb1')
    end

    it 'should revert to previous master connection' do
      @proxy.current = @proxy.master
      @proxy.with_master do
        @proxy.current.should equal(@proxy.master)
      end
      @proxy.current.should equal(@proxy.master)
    end

    it 'should know when in block' do
      @proxy.send(:within_master_block?).should_not be
      @proxy.with_master do
        @proxy.send(:within_master_block?).should be
      end
      @proxy.send(:within_master_block?).should_not be
    end
  end

  context "transaction" do
    it 'should send all to master' do
      @master.should_receive(:select_all).exactly(1)
      @default_slave1.should_receive(:select_all).exactly(0)

      TestModel.transaction do
        @proxy.select_all(@sql)
      end
    end

    it 'should send all to master even if transactions begins on AR::Base' do
      @master.should_receive(:select_all).exactly(1)
      @default_slave1.should_receive(:select_all).exactly(0)

      ActiveRecord::Base.transaction do
        @proxy.select_all(@sql)
      end
    end
  end

  it 'should perform transactions on the master, and selects outside of transaction on the slave' do
    @default_slave1.should_receive(:select_all).exactly(2) # before and after the transaction go to slaves
    @master.should_receive(:select_all).exactly(5)
    @proxy.select_all(@sql)
    ActiveRecord::Base.transaction do
      5.times {@proxy.select_all(@sql)}
    end
    @proxy.select_all(@sql)
  end

  it 'should not switch slaves automatically on selects' do
    @default_slave1.should_receive(:select_one).exactly(6)
    @default_slave2.should_receive(:select_one).exactly(0)
    6.times { @proxy.select_one(@sql) }
  end

  context "next_slave!" do
    it 'should switch to the next slave' do
      @default_slave1.should_receive(:select_one).exactly(1)
      @default_slave2.should_receive(:select_one).exactly(1)

      @proxy.select_one(@sql)
      @proxy.next_slave!
      @proxy.select_one(@sql)
    end

    it 'should not switch when in a with_master-block' do
      @master.should_receive(:select_one).exactly(2)
      @default_slave1.should_not_receive(:select_one)
      @default_slave2.should_not_receive(:select_one)

      @proxy.with_master do
        @proxy.select_one(@sql)
        @proxy.next_slave!
        @proxy.select_one(@sql)
      end
    end
  end

  it 'should send dangerous methods to the master' do
    meths = [:insert, :update, :delete, :execute]
    meths.each do |meth|
      @default_slave1.stub(meth).and_raise(RuntimeError)
      @master.should_receive(meth).and_return(true)
      @proxy.send(meth, @sql)
    end
  end

  it "should not allow master depth to get below 0" do
    @proxy.instance_variable_set("@master_depth", -500)
    @proxy.instance_variable_get("@master_depth").should == -500
    @proxy.with_master {@sql}
    @proxy.instance_variable_get("@master_depth").should == 0
  end

  it 'should pre-generate safe methods' do
    @proxy.should respond_to(:select_value)
    @proxy.select_value(@sql)
    @proxy.should respond_to(:select_value)
  end

  it 'should dynamically generate unsafe methods' do
    @master.should_receive(:unsafe).and_return(true)

    @proxy.should_not respond_to(:unsafe)
    @proxy.unsafe(@sql)
    @proxy.should respond_to(:unsafe)
  end

  it 'should NOT rescue a non Mysql2::Error' do
    @default_slave1.should_receive(:select_all).once.and_raise(RuntimeError.new('some error'))
    @default_slave2.should_not_receive(:select_all)
    @master.should_not_receive(:select_all)
    lambda { @proxy.select_all(@sql) }.should raise_error
  end

  it 'should rescue a Mysql::Error fall back to the master' do
    @default_slave1.should_receive(:select_all).once.and_raise(Mysql2::Error.new('connection error'))
    @default_slave2.should_not_receive(:select_all)
    @master.should_receive(:select_all).and_return(true)
    lambda { @proxy.select_all(@sql) }.should_not raise_error
  end

  it 'should re-raise a Mysql::Error from a query timeout and not fall back to master' do
    @default_slave1.should_receive(:select_all).once.and_raise(Mysql2::Error.new('Timeout waiting for a response from the last query. (waited 5 seconds)'))
    @default_slave2.should_not_receive(:select_all)
    @master.should_not_receive(:select_all)
    lambda { @proxy.select_all(@sql) }.should raise_error
  end

  it 'should reload models from the master' do
    foo = TestModel.create!
    @master.should_receive(:select_all).and_return([{'id' => foo.id}])
    @default_slave1.should_not_receive(:select_all)
    @default_slave2.should_not_receive(:select_all)
    foo.reload
  end

  context "with_pool" do

    it "should switch to default pool if an invalid pool is specified" do
      @default_slave1.should_receive(:select_one).exactly(3)
      @secondary_slave1.should_not_receive(:select_one)
      @secondary_slave2.should_not_receive(:select_one)
      @secondary_slave3.should_not_receive(:select_one)
      @proxy.with_pool('sfdsfsdf') do
        3.times {@proxy.select_one(@sql)}
      end
    end

    it "should switch to default pool if an no pool is specified" do
      @default_slave1.should_receive(:select_one).exactly(1)
      @proxy.with_pool do
        @proxy.select_one(@sql)
      end
    end

    it "should use a different pool if specified" do
      @default_slave1.should_not_receive(:select_one)
      @secondary_slave1.should_receive(:select_one).exactly(3)
      @secondary_slave2.should_not_receive(:select_one)
      @secondary_slave3.should_not_receive(:select_one)
      @proxy.with_pool('secondary') do
        3.times {@proxy.select_one(@sql)}
      end
    end

    it "should different pool should use next_slave! to advance to the next DB" do
      @default_slave1.should_not_receive(:select_one)
      @secondary_slave1.should_receive(:select_one).exactly(2)
      @secondary_slave2.should_receive(:select_one).exactly(1)
      @secondary_slave3.should_receive(:select_one).exactly(1)
      @proxy.with_pool('secondary') do
        4.times do
          @proxy.select_one(@sql)
          @proxy.next_slave!
        end
      end
    end

    it "should switch to master if with_master is specified in an inner block" do
      @master.should_receive(:select_one).exactly(5)
      @default_slave1.should_receive(:select_one).exactly(0)
      @secondary_slave1.should_receive(:select_one).exactly(0)
      @secondary_slave2.should_receive(:select_one).exactly(0)
      @secondary_slave3.should_receive(:select_one).exactly(0)
      @proxy.with_pool('secondary') do
        @proxy.with_master do
          5.times do
            @proxy.select_one(@sql)
            @proxy.next_slave!
          end
        end
      end
    end

    it "should switch to master if with_master is specified in an outer block (with master needs to trump with_pool)" do
      @secondary_slave1.should_receive(:select_one).exactly(0)
      @secondary_slave2.should_receive(:select_one).exactly(0)
      @secondary_slave3.should_receive(:select_one).exactly(0)
      @proxy.with_master do
        @proxy.with_pool('secondary') do
          5.times do
            @proxy.select_one(@sql)
            @proxy.next_slave!
          end
        end
      end
    end

    it "should switch back to previous pool and slave" do
      @proxy.next_slave!

      @proxy.current_pool.name.should eq('default')
      @proxy.current.name.should eq('SlavePools::DefaultDb2')

      @proxy.with_pool('secondary') do
        @proxy.current_pool.name.should eq('secondary')
        @proxy.current.name.should eq('SlavePools::SecondaryDb1')

        @proxy.with_pool('default') do
          @proxy.current_pool.name.should eq('default')
          @proxy.current.name.should eq('SlavePools::DefaultDb2')
        end

        @proxy.current_pool.name.should eq('secondary')
        @proxy.current.name.should eq('SlavePools::SecondaryDb1')
      end

      @proxy.current_pool.name.should eq('default')
      @proxy.current.name.should eq('SlavePools::DefaultDb2')
    end
  end
end

