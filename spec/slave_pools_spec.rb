require_relative 'spec_helper'

describe SlavePools do

  before(:each) do
    SlavePools.pools.each{|_, pool| pool.reset }
    @proxy = SlavePools.proxy
  end

  it 'should delegate next_slave! call to connection proxy' do
    @proxy.should_receive(:next_slave!).exactly(1)
    SlavePools.next_slave!
  end

  it 'should delegate with_pool call to connection proxy' do
    @proxy.should_receive(:with_pool).exactly(1)
    SlavePools.with_pool('test')
  end

  it 'should delegate with_master call to connection proxy' do
    @proxy.should_receive(:with_master).exactly(1)
    SlavePools.with_master
  end

  it 'should delegate current call to connection proxy' do
    @proxy.should_receive(:current).exactly(1)
    SlavePools.current
  end

end

