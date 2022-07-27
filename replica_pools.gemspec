# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'replica_pools/version'

Gem::Specification.new do |s|
  s.name = %q{replica_pools}
  s.version = ReplicaPools::VERSION
  s.summary = "Connection proxy for ActiveRecord for leader / replica setups."
  s.description = "Connection proxy for ActiveRecord for leader / replica setups."
  s.license = 'MIT'

  s.homepage = "https://github.com/kickstarter/replica_pools"
  s.authors = ["Dan Drabik", "Lance Ivy"]
  s.email = "dan@kickstarter.com"

  s.files = Dir.glob("lib/**/*.rb") + %w(LICENSE README.md)
  s.test_files = Dir.glob("spec/**/*.rb")

  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=

  s.add_dependency('activerecord', ["> 6.0", "< 8.0"])
  s.add_development_dependency('mysql2', ["~> 0.5"])
  s.add_development_dependency('rack')
  s.add_development_dependency('rspec')
  s.add_development_dependency('rake')
  s.add_development_dependency('rails')
  s.add_development_dependency('pry')
end
