source "https://rubygems.org"
gemspec

group :development do
  # This allows us to easily switch between different versions of ActiveRecord.
  # To use this in local dev, you can do:
  # ```
  # rm Gemfile.lock
  # ACTIVE_RECORD_VERSION="7.1" bundle install
  # ```
  active_record_version = ENV.fetch("ACTIVE_RECORD_VERSION", nil)
  gem "activerecord", "~> #{active_record_version}.0" if active_record_version&.length&.positive?

  # Just helping out the bundler resolver:
  gem "rails", "> 6.0"
end
