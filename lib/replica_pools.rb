# frozen_string_literal: true

require 'active_record'

# Rails 6+/7+ adapter built on ActiveRecord.connected_to.
# This gem now exposes only the APIs used by Kickstarter (`with_pool`,
# `with_leader`, `config.disable_leader`, `setup!`, and logging helpers).
# Legacy proxy/pool-rotation APIs were intentionally removed in v3.
module ReplicaPools
  # Raised when writes are disallowed by `config.disable_leader`.
  class LeaderDisabled < StandardError
    def to_s
      'Leader database has been disabled. Re-enable with ReplicaPools.config.disable_leader = false.'
    end
  end

  # Minimal runtime configuration supported by the v3 API surface.
  class Config
    attr_accessor :disable_leader

    def initialize
      @disable_leader = false
    end
  end

  module_function

  def config
    @config ||= Config.new
  end

  def with_leader(&)
    raise LeaderDisabled if config.disable_leader

    with_leader_depth do
      ActiveRecord::Base.connected_to(role: :writing, &)
    end
  end

  def with_pool(name, &)
    return yield if within_leader_block?

    with_connected_to(
      role: :reading,
      shard: normalized_shard(name),
      prevent_writes: true,
      fallback_role: :writing,
      &
    )
  end

  def establish_replica_connections
    %i[default admin].each do |pool_name|
      with_pool(pool_name) { ActiveRecord::Base.connection_pool.with_connection(&:active?) }
    end
  end

  def setup!
    establish_replica_connections
  end

  def log(level, message)
    Rails.logger.public_send(level, "[ReplicaPools] #{message}")
  end

  def with_connected_to(role:, fallback_role:, shard: ActiveRecord::Base.current_shard, prevent_writes: false, &)
    if role_available?(role:, shard:, prevent_writes:)
      ActiveRecord::Base.connected_to(role:, shard:, prevent_writes:, &)
    else
      raise LeaderDisabled if config.disable_leader && fallback_role == :writing

      log(:warn, "Falling back to writing role for shard=#{shard} because reading pool is unavailable")
      fallback_prevent_writes = fallback_role == :writing ? false : prevent_writes
      ActiveRecord::Base.connected_to(role: fallback_role, shard: :default, prevent_writes: fallback_prevent_writes, &)
    end
  end

  def role_available?(role:, shard:, prevent_writes:)
    ActiveRecord::Base.connected_to(role:, shard:, prevent_writes:) { ActiveRecord::Base.connection_pool }
    true
  rescue ActiveRecord::ConnectionNotEstablished
    false
  end

  # Legacy pool names now map to the two supported shards.
  # `admin` -> :admin, everything else -> :default
  def normalized_shard(name)
    return :admin if name.to_s == 'admin'

    :default
  end

  def within_leader_block?
    leader_depth.positive?
  end

  def with_leader_depth
    Thread.current[:replica_pools_leader_depth] = leader_depth + 1
    yield
  ensure
    Thread.current[:replica_pools_leader_depth] = [leader_depth - 1, 0].max
  end

  def leader_depth
    Thread.current[:replica_pools_leader_depth].to_i
  end
end
