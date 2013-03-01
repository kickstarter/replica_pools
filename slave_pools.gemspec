# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{slave_pools}
  s.version = "0.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Dan Drabik"]
  s.description = "Connection proxy for ActiveRecord for single master / multiple slave database groups"
  s.email = "dan@kickstarter.com"
  s.extra_rdoc_files = ["LICENSE", "README.rdoc"]
  s.files = ["lib/slave_pools.rb", "lib/slave_pools/active_record_extensions.rb", "lib/slave_pools/connection_proxy.rb", "lib/slave_pools/observer_extensions.rb", "lib/slave_pools/query_cache_compat.rb", "lib/slave_pools/slave_pool.rb", "LICENSE", "README.rdoc", "spec/config/database.yml", "spec/connection_proxy_spec.rb", "spec/slave_pool_spec.rb","spec/slave_pools_spec.rb", "spec/spec_helper.rb", "slave_pools.gemspec"]
  s.has_rdoc = true
  s.homepage = "https://github.com/kickstarter/slave_pools"
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "slave_pools", "--main", "README.rdoc"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.summary = "Connection proxy for ActiveRecord for single master / multiple slave database groups"

  s.add_dependency('activerecord', ["~> 3.2.12"])
  s.add_development_dependency('mysql2', ["~> 0.3.11"])
end
