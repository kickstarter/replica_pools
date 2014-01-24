require_relative 'spec_helper'
require_relative 'config/test_model'

describe SlavePools do

  before(:each) do
    reset_proxy(SlavePools.proxy)

    @test_model = TestModel.create
  end

  it "should use callbacks correctly" do
    TestSub.last.test_model_id.should == @test_model.reload.id
  end

  it "should not throw a stack too deep error" do
    @test_model.should be_valid
  end
end

