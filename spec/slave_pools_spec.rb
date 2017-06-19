require_relative 'spec_helper'

describe ReplicaPools do

  before(:each) do
    ReplicaPools.pools.each{|_, pool| pool.reset }
    @proxy = ReplicaPools.proxy
  end

  it 'should delegate next_replica! call to connection proxy' do
    expect(@proxy).to(receive(:next_replica!).exactly(1))
    ReplicaPools.next_replica!
  end

  it 'should delegate with_pool call to connection proxy' do
    expect(@proxy).to(receive(:with_pool).exactly(1))
    ReplicaPools.with_pool('test')
  end

  it 'should delegate with_leader call to connection proxy' do
    expect(@proxy).to(receive(:with_leader).exactly(1))
    ReplicaPools.with_leader
  end

  it 'should delegate current call to connection proxy' do
    expect(@proxy).to(receive(:current).exactly(1))
    ReplicaPools.current
  end

end

