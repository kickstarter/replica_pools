require_relative 'spec_helper'

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

end
