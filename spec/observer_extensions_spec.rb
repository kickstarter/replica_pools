require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require File.expand_path(File.dirname(__FILE__) + '/config/test_model')

describe SlavePools do

  before(:each) do
    reset_proxy(SlavePools.proxy)
    @observer = TestModelObserver.instance

    @test_model = TestModel.create
  end

  it "should use observers correctly" do
    TestSub.first.test_model_id.should == @test_model.id
  end

  it "should not throw a stack too deep error" do
    @test_model.should be_valid
  end
end

