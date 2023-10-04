require 'rack'
require_relative 'spec_helper'
require_relative 'config/test_model'

describe ReplicaPools::QueryCache do
  before(:each) do
    @sql = 'SELECT NOW()'

    # here we save the real connection pool and checkout a connection from it
    # this lets us verify calls to specific connections in the specs then check back in
    # those connections once each test block is done
    @proxy = ReplicaPools.proxy
    @leader_connection_pool = @proxy.leader.connection_pool
    @leader = @leader_connection_pool.checkout

    # need to checkout the replica connections before connection_pool is mocked since the
    # the same pool object is used for leader and replicas since they have the same connection config
    create_replica_aliases(@proxy)

    # we now mock out the connection pool so it doesn't checkout new connections mid spec run
    # instead we pass our already checked out connection in each test
    leader_connection_pool = instance_double("ActiveRecord::ConnectionPool")
    allow(@proxy.leader).to receive(:connection_pool).and_return(leader_connection_pool)
    allow(leader_connection_pool).to receive(:checkout).and_return(@leader)
    allow(leader_connection_pool).to receive(:checkin)

    @leader.clear_query_cache

    reset_proxy(@proxy)
  end

  after(:each) do
    @leader_connection_pool.checkin(@leader)
    close_replica_aliases(@proxy)
  end

  it 'should cache queries using select_all' do
    ActiveRecord::Base.cache do
      # next_replica will be called and switch to the replicaDatabase2
      @default_replica1.should_receive(:select_all).exactly(1).and_return([])
      @default_replica2.should_not_receive(:select_all)
      @leader.should_not_receive(:select_all)
      3.times { @proxy.select_all(@sql) }
      @leader.query_cache.keys.size.should == 1
    end
  end

  it 'should invalidate the cache on insert, delete and update' do
    ActiveRecord::Base.cache do
      meths = [:insert, :update, :delete, :insert, :update]
      meths.each do |meth|
        @leader.should_receive("exec_#{meth}").and_return(true)
      end

      @default_replica1.should_receive(:select_all).exactly(5).and_return([])
      @default_replica2.should_receive(:select_all).exactly(0)
      5.times do |i|
        @proxy.select_all(@sql)
        @proxy.select_all(@sql)
        @leader.query_cache.keys.size.should == 1
        @proxy.send(meths[i], '')
        @leader.query_cache.keys.size.should == 0
      end
    end
  end

  describe "using querycache middleware" do
    select_all_queries_lambda = lambda do |env|
      @default_replica1.should_receive(:select_all).exactly(1).and_return([])
      @default_replica2.should_not_receive(:select_all)
      @leader.should_not_receive(:select_all)
      3.times { @proxy.select_all(@sql) }
      @proxy.next_replica!
      3.times { @proxy.select_all(@sql) }
      @proxy.next_replica!
      3.times { @proxy.select_all(@sql)}
      @leader.query_cache.keys.size.should == 1
      [200, {}, nil]
    end

    insert_update_delete_lambda = lambda do |env|
      meths = [:insert, :update, :delete, :insert, :update]
      meths.each do |meth|
        @leader.should_receive("exec_#{meth}").and_return(true)
      end

      @default_replica1.should_receive(:select_all).exactly(5).and_return([])
      @default_replica2.should_receive(:select_all).exactly(0)
      5.times do |i|
        @proxy.select_all(@sql)
        @proxy.select_all(@sql)
        @leader.query_cache.keys.size.should == 1
        @proxy.send(meths[i], '')
        @leader.query_cache.keys.size.should == 0
      end
      [200, {}, nil]
    end

    def executor
      @executor ||= Class.new(ActiveSupport::Executor).tap do |exe|
        ActiveRecord::QueryCache.install_executor_hooks(exe)
      end
    end

    if Gem::Version.new(ActiveRecord.version) < Gem::Version.new('5.0')

      it 'should cache queries using select_all' do
        mw = ActiveRecord::QueryCache.new(select_all_queries_lambda)
        mw.call({})
      end

      it 'should invalidate the cache on insert, delete and update' do
        mw = ActiveRecord::QueryCache.new(insert_update_delete_lambda)
        mw.call({})
      end
    else
      it 'should cache queries using select_all' do
        executor.wrap { select_all_queries_lambda }
      end

      it 'should invalidate the cache on insert, delete and update' do
        executor.wrap { insert_update_delete_lambda }
      end
    end
  end

  describe '.pluck regression test' do
    it 'should work with query caching' do
      TestModel.connection.enable_query_cache!
      expect(TestModel.pluck(:id).count).to eql TestModel.all.count
    end

    it 'should work if query cache is not enabled' do
      TestModel.connection.disable_query_cache!
      expect(TestModel.pluck(:id).count).to eql TestModel.all.count
    end
  end
end
