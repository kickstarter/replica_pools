require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe SlavePools do

  before(:each) do
    ActiveRecord::Base.configurations = SLAVE_POOLS_SPEC_CONFIG
    ActiveRecord::Base.establish_connection :test
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Migration.create_table(:master_models, :force => true) {}
    class MasterModel < ActiveRecord::Base; end
    ActiveRecord::Migration.create_table(:foo_models, :force => true) {|t| t.string :bar}
    class FooModel < ActiveRecord::Base; end
    @sql = 'SELECT NOW()'
  end

  describe "standard setup" do
    before(:each) do
      SlavePools.config.master_models = ['MasterModel']
      SlavePools::ConnectionProxy.setup!
      @proxy = ActiveRecord::Base.connection_proxy
      @slave_pool_hash = @proxy.slave_pools
      @slave_pool_array = @slave_pool_hash.values
      @master = @proxy.master.retrieve_connection
      # creates instance variables (@default_slave1, etc.) for each slave based on the order they appear in the slave_pool
      # ruby 1.8.7 doesn't support ordered hashes, so we assign numbers to the slaves this way, and not the order in the yml file
      # to prevent @default_slave1 from being different on different systems
      ['default', 'secondary'].each do |pool_name|
        @slave_pool_hash[pool_name.to_sym].slaves.each_with_index do |slave, i|
          instance_variable_set("@#{pool_name}_slave#{i + 1}", slave.retrieve_connection)
        end
      end
    end

    it 'AR::B should respond to #connection_proxy' do
      ActiveRecord::Base.connection_proxy.should be_kind_of(SlavePools::ConnectionProxy)
    end

    it 'FooModel#connection should return an instance of SlavePools::ConnectionProxy' do
      FooModel.connection.should be_kind_of(SlavePools::ConnectionProxy)
    end

    it 'MasterModel#connection should not return an instance of SlavePools::ConnectionProxy' do
      MasterModel.connection.should_not be_kind_of(SlavePools::ConnectionProxy)
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

    it 'should handle nested with_master-blocks correctly' do
      @proxy.current.should_not == @proxy.master
      @proxy.with_master do
        @proxy.current.should == @proxy.master
        @proxy.with_master do
          @proxy.current.should == @proxy.master
          @proxy.with_master do
            @proxy.current.should == @proxy.master
          end
          @proxy.current.should == @proxy.master
        end
        @proxy.current.should == @proxy.master
      end
      @proxy.current.should_not == @proxy.master
    end

    it 'should perform transactions on the master' do
      @master.should_receive(:select_all).exactly(5)
      @default_slave1.should_receive(:select_all).exactly(0)
      ActiveRecord::Base.transaction({}) do
        5.times {@proxy.select_all(@sql)}
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

    it 'should not switch to the next reader on selects' do
      @default_slave1.should_receive(:select_one).exactly(6)
      @default_slave2.should_receive(:select_one).exactly(0)
      6.times { @proxy.select_one(@sql) }
    end

    it '#next_slave! should switch to the next slave' do
      @default_slave1.should_receive(:select_one).exactly(3)
      @default_slave2.should_receive(:select_one).exactly(7)
      3.times { @proxy.select_one(@sql) }
      @proxy.next_slave!
      7.times { @proxy.select_one(@sql) }
    end

    it 'should switch if next reader is explicitly called' do
      @default_slave1.should_receive(:select_one).exactly(3)
      @default_slave2.should_receive(:select_one).exactly(3)
      6.times do
        @proxy.select_one(@sql)
        @proxy.next_slave!
      end
    end

    it 'should not switch to the next reader when whithin a with_master-block' do
      @master.should_receive(:select_one).twice
      @default_slave1.should_not_receive(:select_one)
      @default_slave2.should_not_receive(:select_one)
      @proxy.with_master do
        2.times { @proxy.select_one(@sql) }
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

    it "should send writes to the master, even if current gets called for a write" do
      @proxy.instance_variable_set("@master_depth", 0)
      @master.should_receive(:update).and_return(true)
      @proxy.send(:send_to_current, :update, @sql, {})
    end

    it "should not allow master depth to get below 0" do
      @proxy.instance_variable_set("@master_depth", -500)
      @proxy.instance_variable_get("@master_depth").should == -500
      @proxy.with_master {@sql}
      @proxy.instance_variable_get("@master_depth").should == 0
    end

    it 'should dynamically generate safe methods' do
      @proxy.should_not respond_to(:select_value)
      @proxy.select_value(@sql)
      @proxy.should respond_to(:select_value)
    end

    it 'should cache queries using select_all' do
      ActiveRecord::Base.cache do
        # next_slave will be called and switch to the SlaveDatabase2
        @default_slave1.should_receive(:select_all).exactly(1).and_return([])
        @default_slave2.should_not_receive(:select_all)
        @master.should_not_receive(:select_all)
        3.times { @proxy.select_all(@sql) }
        @master.query_cache.keys.size.should == 1
      end
    end

    it 'should invalidate the cache on insert, delete and update' do
      ActiveRecord::Base.cache do
        meths = [:insert, :update, :delete, :insert, :update]
        meths.each do |meth|
          @master.should_receive(meth).and_return(true)
        end
        @default_slave1.should_receive(:select_all).exactly(5).and_return([])
        @default_slave2.should_receive(:select_all).exactly(0)
        5.times do |i|
          @proxy.select_all(@sql)
          @proxy.select_all(@sql)
          @master.query_cache.keys.size.should == 1
          @proxy.send(meths[i])
          @master.query_cache.keys.size.should == 0
        end
      end
    end

    describe "using querycache middleware" do
      it 'should cache queries using select_all' do
        mw = ActiveRecord::QueryCache.new lambda { |env|
          @default_slave1.should_receive(:select_all).exactly(1).and_return([])
          @default_slave2.should_not_receive(:select_all)
          @master.should_not_receive(:select_all)
          3.times { @proxy.select_all(@sql) }
          @proxy.next_slave!
          3.times { @proxy.select_all(@sql) }
          @proxy.next_slave!
          3.times { @proxy.select_all(@sql)}
          @master.query_cache.keys.size.should == 1
        }
        mw.call({})
      end

      it 'should invalidate the cache on insert, delete and update' do
        mw = ActiveRecord::QueryCache.new lambda { |env|
          meths = [:insert, :update, :delete, :insert, :update]
          meths.each do |meth|
            @master.should_receive(meth).and_return(true)
          end
          @default_slave1.should_receive(:select_all).exactly(5).and_return([])
          @default_slave2.should_receive(:select_all).exactly(0)
          5.times do |i|
            @proxy.select_all(@sql)
            @proxy.select_all(@sql)
            @master.query_cache.keys.size.should == 1
            @proxy.send(meths[i])
            @master.query_cache.keys.size.should == 0
          end
        }
        mw.call({})
      end
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

    it 'should try to reconnect the master connection after the master has failed' do
      @master.should_receive(:update).and_raise(RuntimeError)
      lambda { @proxy.update(@sql) }.should raise_error
      @master.should_receive(:reconnect!).and_return(true)
      @master.should_receive(:insert).and_return(1)
      @proxy.insert(@sql)
    end

    it 'should reload models from the master' do
      foo = FooModel.create!(:bar => 'baz')
      foo.bar = "not_saved"
      @default_slave1.should_not_receive(:select_all)
      @default_slave2.should_not_receive(:select_all)
      foo.reload
      # we didn't stub @master#select_all here, check that we actually hit the db
      foo.bar.should == 'baz'
    end

    context "Using with_pool call" do

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
    end
  end
end

