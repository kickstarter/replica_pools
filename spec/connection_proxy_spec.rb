require_relative 'spec_helper'

describe ReplicaPools do
  around do |example|
    previous_disable_leader = described_class.config.disable_leader
    example.run
  ensure
    described_class.config.disable_leader = previous_disable_leader
    Thread.current[:replica_pools_leader_depth] = nil
  end

  describe '.with_connected_to' do
    it 'uses requested role and shard when available' do
      result = described_class.with_connected_to(role: :reading, fallback_role: :writing, shard: :admin, prevent_writes: true) do
        [ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard]
      end

      expect(result).to eq([:reading, :admin])
    end

    it 'falls back to writing role when requested role is unavailable' do
      allow(described_class).to receive(:role_available?).and_return(false)

      result = described_class.with_connected_to(role: :reading, fallback_role: :writing, shard: :admin, prevent_writes: true) do
        [ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard]
      end

      expect(result).to eq([:writing, :default])
    end

    it 'raises LeaderDisabled when fallback to writing is blocked' do
      described_class.config.disable_leader = true
      allow(described_class).to receive(:role_available?).and_return(false)

      expect do
        described_class.with_connected_to(role: :reading, fallback_role: :writing, shard: :default, prevent_writes: true) { :ok }
      end.to raise_error(described_class::LeaderDisabled)
    end
  end
end
