require_relative 'spec_helper'

describe ReplicaPools do
  around do |example|
    example.run
  ensure
    Thread.current[:replica_pools_leader_depth] = nil
  end

  describe '.normalized_shard' do
    it 'returns admin for admin pool name' do
      expect(described_class.normalized_shard(:admin)).to eq(:admin)
      expect(described_class.normalized_shard('admin')).to eq(:admin)
    end

    it 'returns default for unknown pool names' do
      expect(described_class.normalized_shard(:default)).to eq(:default)
      expect(described_class.normalized_shard(:unknown)).to eq(:default)
      expect(described_class.normalized_shard(nil)).to eq(:default)
    end
  end

  describe '.with_leader_depth' do
    it 'tracks nested leader context with depth counter' do
      expect(described_class.within_leader_block?).to be(false)

      described_class.with_leader_depth do
        expect(described_class.within_leader_block?).to be(true)

        described_class.with_leader_depth do
          expect(described_class.within_leader_block?).to be(true)
        end

        expect(described_class.within_leader_block?).to be(true)
      end

      expect(described_class.within_leader_block?).to be(false)
    end

    it 'does not leave depth below zero' do
      Thread.current[:replica_pools_leader_depth] = -500

      described_class.with_leader_depth { :ok }

      expect(Thread.current[:replica_pools_leader_depth]).to eq(0)
    end
  end
end
