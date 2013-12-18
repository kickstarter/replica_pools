# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{slave_pools}
  s.version = "0.1.2"
  s.summary = "Connection proxy for ActiveRecord for master / replica setups."
  s.description = "Connection proxy for ActiveRecord for master / replica setups."
  s.license = 'MIT'

  s.homepage = "https://github.com/kickstarter/slave_pools"
  s.authors = ["Dan Drabik", "Lance Ivy"]
  s.email = "dan@kickstarter.com"

  s.files = Dir.glob("lib/**/*.rb")
  s.test_files = Dir.glob("spec/**/*.rb") + %w(LICENSE README.md)

  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=

  s.add_dependency('activerecord', ["~> 3.2.12"])
  s.add_development_dependency('mysql2', ["~> 0.3.11"])
  s.add_development_dependency('rspec')
  s.add_development_dependency('rake')
  s.add_development_dependency('rails')
end
