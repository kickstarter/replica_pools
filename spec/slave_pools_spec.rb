require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require SLAVE_POOLS_SPEC_DIR + '/../lib/slave_pools'

describe SlavePools do

  before(:all) do
    ActiveRecord::Base.configurations = SLAVE_POOLS_SPEC_CONFIG
    ActiveRecord::Base.establish_connection :test
  end
  
  context "with no setup" do
    it "should not error out if next slave is called and SlavePools is not set up" do
      SlavePools.should_receive(:active?).and_return(false)
      SlavePools.next_slave!.should be_nil
    end    
  end
  
  describe "Slave Pool Wrapper calls" do
    before(:each) do
      SlavePools.setup!
      @proxy = ActiveRecord::Base.connection_proxy
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
    
    it 'should send with_slave call to connection proxy' do
      @proxy.should_receive(:with_slave).exactly(1)
      SlavePools.with_slave
    end

  end

end

