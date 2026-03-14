# frozen_string_literal: true

begin
  require "de_dupe"
rescue LoadError
  raise LoadError,
    "The 'de-dupe' gem is required for Lepus unique middleware. " \
    "Add `gem 'de-dupe'` to your Gemfile."
end

unless DeDupe.config.redis
  raise Lepus::Error,
    "DeDupe is not configured with Redis. " \
    "Call DeDupe.configure { |c| c.redis = Redis.new } before requiring 'lepus/unique'."
end

require_relative "producers/middlewares/unique"
require_relative "consumers/middlewares/unique"
