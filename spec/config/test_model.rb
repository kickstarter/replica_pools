class TestModel < ActiveRecord::Base
  has_many :test_subs

  after_create :create_sub
  def create_sub
    ActiveRecord::Base.logger.info "in callback"
    TestSub.create(:test_model=>self)
  end
end

class TestSub < ActiveRecord::Base
  belongs_to :test_model
end
