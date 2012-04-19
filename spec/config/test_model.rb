class TestModel < ActiveRecord::Base
  has_many :test_subs
end

class TestSub < ActiveRecord::Base
  belongs_to :test_model
end

class TestModelObserver < ActiveRecord::Observer
  
  def after_create(test_model)
    ActiveRecord::Base.logger.info "in observer"
    TestSub.create(:test_model=>test_model)
    TestModel.first
  end
end



