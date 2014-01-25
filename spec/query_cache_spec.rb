require 'rack'
require_relative 'spec_helper'

describe SlavePools::QueryCache do
  before(:each) do
    @sql = 'SELECT NOW()'

    @proxy = SlavePools.proxy
    @master = @proxy.master.retrieve_connection

    @master.clear_query_cache

    reset_proxy(@proxy)
    create_slave_aliases(@proxy)
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
        @master.should_receive("exec_#{meth}").and_return(true)
      end

      @default_slave1.should_receive(:select_all).exactly(5).and_return([])
      @default_slave2.should_receive(:select_all).exactly(0)
      5.times do |i|
        @proxy.select_all(@sql)
        @proxy.select_all(@sql)
        @master.query_cache.keys.size.should == 1
        @proxy.send(meths[i], '')
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
        [200, {}, nil]
      }
      mw.call({})
    end

    it 'should invalidate the cache on insert, delete and update' do
      mw = ActiveRecord::QueryCache.new lambda { |env|
        meths = [:insert, :update, :delete, :insert, :update]
        meths.each do |meth|
          @master.should_receive("exec_#{meth}").and_return(true)
        end

        @default_slave1.should_receive(:select_all).exactly(5).and_return([])
        @default_slave2.should_receive(:select_all).exactly(0)
        5.times do |i|
          @proxy.select_all(@sql)
          @proxy.select_all(@sql)
          @master.query_cache.keys.size.should == 1
          @proxy.send(meths[i], '')
          @master.query_cache.keys.size.should == 0
        end
        [200, {}, nil]
      }
      mw.call({})
    end
  end

end
