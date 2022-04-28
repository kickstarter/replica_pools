# ReplicaPools

Easy Single Leader / Multiple Replica Setup for use in Ruby/Rails projects

[![Spec](https://github.com/kickstarter/replica_pools/actions/workflows/spec.yml/badge.svg)](https://github.com/kickstarter/replica_pools/actions/workflows/spec.yml)

## Overview

ReplicaPools replaces ActiveRecord's connection with a proxy that routes database interactions to the proper connection. Safe (whitelisted) methods may go to the current replica, and all other methods go to the leader connection.

ReplicaPools also provides helpers so you can customize your replica strategy. You can organize replicas into pools and cycle through them (e.g. in a before_filter). You can make the connection default to the leader, or the default replica pool, and then use block helpers to temporarily change the behavior (e.g. in an around_filter).

- Uses a naming convention in database.yml to designate replica pools.
- Defaults to a given replica pool, but may also be configured to default to leader.
- Routes database interactions (queries) to the right connection
  - Whitelisted queries go to the current connection (might be a replica).
  - All queries inside a transaction run on leader.
  - All other queries are also sent to the leader connection.
- Supports ActiveRecord's in-memory query caching.
- Helper methods can be used to easily load balance replicas, route traffic to different replica pools, or run directly against leader. (examples below)

## Not Supported

- Sharding.
- Automatic load balancing strategies.
- Replica weights. You can accomplish this in your own load balancing strategy.
- Whitelisting models that always use leader.
- Blacklisting poorly performing replicas. This could cause load spikes on your leader. Whatever provisions your database.yml should make this choice.

## Installation and Setup

Add to your Gemfile:

    gem 'replica_pools'

### Adding Replicas

Add entries to your database.yml in the form of `<environment>_pool_<pool_name>_name_<db_name>`

For example:

    # Leader connection for production environment
    production:
      adapter: mysql
      database: myapp_production
      username: root
      password:
      host: localhost

    # Default pool for production environment
    production_pool_default_name_replica1:
      adapter: mysql
      database: replica_db1
      username: root
      password:
      host: 10.0.0.2
    production_pool_default_name_replica2:
      ...

    # Special pool for production environment
    production_pool_admin_name_replica1:
      ...
    production_pool_admin_name_another_replica:
      ...

### Simulating Replicas

If you don't have any replicas (e.g. in your development environment), ReplicaPools will create a default pool containing only leader. But if you want to mimic your production environment more closely you can create a read-only mysql user and use it like a replica.

    # Development connection
    development: &dev
      adapter: mysql
      database: myapp_development
      username: root
      password:
      host: localhost

    development_pool_default_name_replica1:
      username: readonly
      <<: &dev

Don't do this in your test environment if you use transactional tests though! The replica connections won't be able to see any fixtures or factory data.

### Configuring

Add a `config/initializers/replica_pools.rb` if you want to change config settings:

    ReplicaPools.config.defaults_to_leader = true

## Usage

Toggle to next replica:

    ReplicaPools.next_replica!

Specify a pool besides the default:

    ReplicaPools.with_pool('other_pool') { #do stuff }

Specifically use the leader for a call:

    ReplicaPools.with_leader { #do stuff }

### Load Balancing

If you have multiple replicas in a pool and you'd like to load balance requests between them, you can easily accomplish this with a `before_filter`:

    class ApplicationController < ActionController::Base
      after_filter    :switch_to_next_replica

      protected

      def switch_to_next_replica
        ReplicaPools.next_replica!
      end
    end

### Specialty Pools

If you have specialized replica pools and would like to use them for different controllers or actions, you can use an `around_filter`:

    class ApplicationController < ActionController::Base
      around_filter   :use_special_replicas

      protected

      def use_special_replicas
        ReplicaPools.with_pool('special'){ yield }
      end
    end

### Replica Lag

By default, writes are sent to the leader and reads are sent to replicas. But replicas might lag behind the leader by seconds or even minutes. So if you write to leader during a request you probably want to read from leader in that request as well. You may even want to read from the leader on the _next_ request, to cover redirects.

Here's one way to accomplish that:

    class ApplicationController < ActionController::Base

      around_filter   :stick_to_leader_for_updates
      around_filter   :use_leader_for_redirect #goes with above

      def stick_to_leader_for_updates
        if request.get?
          yield
        else
          ReplicaPools.with_leader { yield }
          session[:stick_to_leader] = 1
        end
      end

      def use_leader_for_redirect
        if session[:stick_to_leader]
          session[:stick_to_leader] = nil
          ReplicaPools.with_leader { yield }
        else
          yield
        end
      end
    end

## Disabling Leader

To disable queries to the leader database -- for instance, in a production
console -- set the disable_leader configuration to false. This will raise
a ReplicaPools::LeaderDisabled error:

ReplicaPools.config.disable_leader = false

## Running specs

Tests are run against MySQL 5.6 using docker-compose. 🐋

To get set up, first run:

```bash
$ docker-compose up
$ bundle install
$ bundle exec rake bootstrap
```

Then you can run tests with:

```bash
$ bundle exec rake spec
```

## Releasing a New Version

First bump the version as appropriate in `lib/replica_pools/version.rb` and then run `bundle exec rake release`. This will push git tags to github and package and push the gem to rubygems.org.

## Authors

Author: Dan Drabik, Lance Ivy

Copyright (c) 2012-2021, Kickstarter

Released under the MIT license

## See also

### MultiDb

The project is based on:

- https://github.com/schoefmax/multi_db

### Masochism

The original leader/replica plugin:

- http://github.com/technoweenie/masochism
