# frozen_string_literal: true

require "bundler/setup"

require "dotenv/load"
require "pry"
require "lepus"
require "simplecov"

SimpleCov.start

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  def reset_config!
    Lepus.instance_variable_set(:@config, nil)
    Lepus::ProcessRegistry.reset!
    Lepus::Consumers::WorkerFactory.send(:clear_all)
    Lepus::Producers::Hooks.reset!
  end
end
