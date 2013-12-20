# SlavePools

Easy Single Master/ Multiple Slave Setup for use in Ruby/Rails projects

## Overview

SlavePools replaces ActiveRecord's connection with a proxy that routes database interactions to the proper connection. Safe (whitelisted) methods may go to the current replica, and all other methods go to the master connection.

SlavePools also provides helpers so you can customize your replica strategy. You can organize replicas into pools and cycle through them (e.g. in a before_filter). You can make the connection default to the master, or the default replica pool, and then use block helpers to temporarily change the behavior (e.g. in an around_filter).

* Uses a naming convention in database.yml to designate replica pools.
* Defaults to a given replica pool, but may also be configured to default to master.
* Routes database interactions (queries) to the right connection
  * Whitelisted queries go to the current connection (might be a replica).
  * All queries inside a transaction run on master.
  * All other queries are also sent to the master connection.
* Supports ActiveRecord's in-memory query caching.
* Helper methods can be used to easily load balance replicas, route traffic to different replica pools, or run directly against master. (examples below)

## Not Supported

* Sharding.
* Automatic load balancing strategies.
* Replica weights. You can accomplish this in your own load balancing strategy.
* Whitelisting models that always use master.
* Blacklisting poorly performing replicas. This could cause load spikes on your master. Whatever provisions your database.yml should make this choice.

## Installation and Setup

Add to your Gemfile:

    gem 'slave_pools'

### Adding Replicas

Add entries to your database.yml in the form of `<environment>_pool_<pool_name>_name_<db_name>`

For example:

    # Master connection for production environment
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

If you don't have any replicas (e.g. in your development environment), SlavePools will create a default pool containing only master. But if you want to mimic your production environment more closely you can create a read-only mysql user and use it like a replica.

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

Add a `config/initializers/slave_pools.rb` if you want to change config settings:

    SlavePools.config.defaults_to_master = true

## Usage

Toggle to next replica:

    SlavePools.next_slave!

Specify a pool besides the default:

    SlavePools.with_pool('other_pool') { #do stuff }

Specifically use the master for a call:

    SlavePools.with_master { #do stuff }

### Load Balancing

If you have multiple replicas in a pool and you'd like to load balance requests between them, you can easily accomplish this with a `before_filter`:

    class ApplicationController < ActionController::Base
      after_filter    :switch_to_next_slave

      protected

      def switch_to_next_slave
        SlavePools.next_slave!
      end
    end

### Specialty Pools

If you have specialized replica pools and would like to use them for different controllers or actions, you can use an `around_filter`:

    class ApplicationController < ActionController::Base
      around_filter   :use_special_replicas

      protected

      def use_special_replicas
        SlavePools.with_pool('special'){ yield }
      end
    end

### Replica Lag

By default, writes are sent to the master and reads are sent to replicas. But replicas might lag behind the master by seconds or even minutes. So if you write to master during a request you probably want to read from master in that request as well. You may even want to read from the master on the _next_ request, to cover redirects.

Here's one way to accomplish that:

    class ApplicationController < ActionController::Base

      around_filter   :stick_to_master_for_updates
      around_filter   :use_master_for_redirect #goes with above

      def stick_to_master_for_updates
        if request.get?
          yield
        else
          SlavePools.with_master { yield }
          session[:stick_to_master] = 1
        end
      end

      def use_master_for_redirect
        if session[:stick_to_master]
          session[:stick_to_master] = nil
          SlavePools.with_master { yield }
        else
          yield
        end
      end
    end

## Running specs

If you haven't already, install the rspec gem, then set up your database
with a test database and a read_only user.

To match spec/config/database.yml, you can:

    mysql>
      create database test_db;
      create user 'read_only'@'localhost' identified by 'readme';
      grant select on test_db.* to 'read_only'@'localhost';

From the plugin directory, run:

    rspec spec

## Authors

Author: Dan Drabik, Lance Ivy

Copyright (c) 2012-2013, Kickstarter

Released under the MIT license

## See also

### MultiDb

The project is based on:

* https://github.com/schoefmax/multi_db

### Masochism

The original master/slave plugin:

* http://github.com/technoweenie/masochism
