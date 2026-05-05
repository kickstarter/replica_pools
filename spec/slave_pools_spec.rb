require_relative 'spec_helper'

describe ReplicaPools do
  around do |example|
    previous_disable_leader = described_class.config.disable_leader
    example.run
  ensure
    described_class.config.disable_leader = previous_disable_leader
    Thread.current[:replica_pools_leader_depth] = nil
  end

  describe '.with_leader' do
    it 'yields and returns block value' do
      result = described_class.with_leader { :ok }
      expect(result).to eq(:ok)
    end

    it 'allows writes in a leader block' do
      key = "leader-#{SecureRandom.hex(8)}"

      expect do
        described_class.with_leader { TestModel.create!(key:, value: 1) }
      end.to change(TestModel, :count).by(1)
    end

    context 'when leader is disabled' do
      before { described_class.config.disable_leader = true }

      it 'raises LeaderDisabled' do
        expect { described_class.with_leader { :ok } }.to raise_error(described_class::LeaderDisabled)
      end
    end
  end

  describe '.with_pool' do
    it 'yields and returns block value for admin pool' do
      result = described_class.with_pool(:admin) { :ok }
      expect(result).to eq(:ok)
    end

    it 'falls back to default for unknown pools' do
      result = described_class.with_pool(:unknown_pool_name) { :ok }
      expect(result).to eq(:ok)
    end

    it 'prevents writes on reading role' do
      key = "read-role-#{SecureRandom.hex(8)}"

      expect do
        described_class.with_pool(:default) { TestModel.create!(key:, value: 1) }
      end.to raise_error(ActiveRecord::ReadOnlyError)
    end

    it 'allows writes when nested inside with_leader' do
      key = "nested-#{SecureRandom.hex(8)}"

      expect do
        described_class.with_leader do
          described_class.with_pool(:admin) do
            TestModel.create!(key:, value: 1)
          end
        end
      end.to change(TestModel, :count).by(1)
    end

    it 'falls back to writing role when reading role unavailable' do
      key = "fallback-write-#{SecureRandom.hex(8)}"

      allow(described_class).to receive(:role_available?).and_return(false)

      expect do
        described_class.with_pool(:admin) { TestModel.create!(key:, value: 1) }
      end.to change(TestModel, :count).by(1)
    end
  end

  describe '.log' do
    it 'prefixes log output with ReplicaPools tag' do
      allow(Rails.logger).to receive(:info)

      described_class.log(:info, 'test message')
      expect(Rails.logger).to have_received(:info).with('[ReplicaPools] test message')
    end
  end
end
