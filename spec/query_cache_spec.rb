require_relative 'spec_helper'

describe ReplicaPools do
  around do |example|
    previous_disable_leader = described_class.config.disable_leader
    example.run
  ensure
    described_class.config.disable_leader = previous_disable_leader
    Thread.current[:replica_pools_leader_depth] = nil
  end

  describe 'query behavior' do
    before do
      TestModel.delete_all
      3.times { |idx| TestModel.create!(key: "seed-#{idx}", value: idx) }
    end

    it 'works with query cache enabled when reading via with_pool' do
      TestModel.connection.enable_query_cache!

      result = described_class.with_pool(:default) { TestModel.pluck(:id) }

      expect(result.count).to eq(TestModel.count)
    ensure
      TestModel.connection.disable_query_cache!
    end

    it 'works without query cache when reading via with_pool' do
      TestModel.connection.disable_query_cache!

      result = described_class.with_pool(:default) { TestModel.ids }

      expect(result.count).to eq(TestModel.count)
    end

    it 'writes in with_leader and reads in with_pool' do
      created_id = described_class.with_leader do
        TestModel.create!(key: 'leader-write', value: 99).id
      end

      fetched_id = described_class.with_pool(:default) { TestModel.find(created_id).id }
      expect(fetched_id).to eq(created_id)
    end
  end
end
