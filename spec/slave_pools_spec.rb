require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe SlavePools do

  context "with no setup" do
    it "should not error out if next slave is called and SlavePools is not set up" do
      SlavePools.should_receive(:active?).and_return(false)
      SlavePools.next_slave!.should be_nil
    end

    it "should not error out if current is called and SlavePools is not set up" do
      SlavePools.should_receive(:active?).and_return(false)
      SlavePools.current.should be_nil
    end

    it "should yield on a with_pool call if slave_pools is not active" do
      SlavePools.should_receive(:active?).and_return(false)
      ActiveRecord::Base.connection.should_receive(:execute)
      SlavePools.with_pool('admin') {ActiveRecord::Base.connection.execute(@sql)}
    end

    it "should yield on a with_master call if slave_pools is not active" do
      SlavePools.should_receive(:active?).and_return(false)
      ActiveRecord::Base.connection.should_receive(:execute)
      SlavePools.with_master {ActiveRecord::Base.connection.execute(@sql)}
    end
  end

  describe "with setup" do
    before(:each) do
      SlavePools.setup!
      @proxy = SlavePools.proxy
    end

    it 'should send next_slave! call to connection proxy' do
      ActiveRecord::Base.should_receive(:respond_to?).exactly(1)
      SlavePools.active?
    end

    it 'should send next_slave! call to connection proxy' do
      @proxy.should_receive(:next_slave!).exactly(1)
      SlavePools.next_slave!
    end

    it 'should send with_pool call to connection proxy' do
      @proxy.should_receive(:with_pool).exactly(1)
      SlavePools.with_pool('test')
    end

    it 'should send with_master call to connection proxy' do
      @proxy.should_receive(:with_master).exactly(1)
      SlavePools.with_master
    end

    it 'should send current call to connection proxy' do
      @proxy.should_receive(:current).exactly(1)
      SlavePools.current
    end

  end

end

