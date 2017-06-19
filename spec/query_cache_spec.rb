require 'rack'
require_relative 'spec_helper'

describe ReplicaPools::QueryCache do
  before(:each) do
    @sql = 'SELECT NOW()'

    @proxy = ReplicaPools.proxy
    @leader = @proxy.leader.retrieve_connection

    @leader.clear_query_cache

    reset_proxy(@proxy)
    create_replica_aliases(@proxy)
  end

  it 'should cache queries using select_all' do
    ActiveRecord::Base.cache do
      # next_replica will be called and switch to the replicaDatabase2
      expect(@default_replica1).to(receive(:select_all).exactly(1).and_return([]))
      expect(@default_replica2).to_not(receive(:select_all))
      expect(@leader).to_not(receive(:select_all))
      3.times { @proxy.select_all(@sql) }
      expect(@leader.query_cache.keys.size).to(eq(1))
    end
  end

  it 'should invalidate the cache on insert, delete and update' do
    ActiveRecord::Base.cache do
      meths = [:insert, :update, :delete, :insert, :update]
      meths.each do |meth|
        expect(@leader).to(receive("exec_#{meth}").and_return(true))
      end

      expect(@default_replica1).to(receive(:select_all).exactly(5).and_return([]))
      expect(@default_replica2).to(receive(:select_all).exactly(0))
      5.times do |i|
        @proxy.select_all(@sql)
        @proxy.select_all(@sql)
        expect(@leader.query_cache.keys.size).to(eq(1))
        @proxy.send(meths[i], '')
        expect(@leader.query_cache.keys.size).to(eq(0))
      end
    end
  end

  describe "using querycache middleware" do
    it 'should cache queries using select_all' do
      mw = ActiveRecord::QueryCache.new lambda { |env|
        expect(@default_replica1).to(receive(:select_all).exactly(1).and_return([]))
        expect(@default_replica2).to_not(receive(:select_all))
        expect(@leader).to_not(receive(:select_all))
        3.times { @proxy.select_all(@sql) }
        @proxy.next_replica!
        3.times { @proxy.select_all(@sql) }
        @proxy.next_replica!
        3.times { @proxy.select_all(@sql)}
        expect(@leader.query_cache.keys.size).to(eq(1))
        [200, {}, nil]
      }
      mw.call({})
    end

    it 'should invalidate the cache on insert, delete and update' do
      mw = ActiveRecord::QueryCache.new lambda { |env|
        meths = [:insert, :update, :delete, :insert, :update]
        meths.each do |meth|
          expect(@leader).to(receive("exec_#{meth}").and_return(true))
        end

        expect(@default_replica1).to(receive(:select_all).exactly(5).and_return([]))
        expect(@default_replica2).to(receive(:select_all).exactly(0))
        5.times do |i|
          @proxy.select_all(@sql)
          @proxy.select_all(@sql)
          expect(@leader.query_cache.keys.size).to(eq(1))
          @proxy.send(meths[i], '')
          expect(@leader.query_cache.keys.size).to(eq(0))
        end
        [200, {}, nil]
      }
      mw.call({})
    end
  end

end
