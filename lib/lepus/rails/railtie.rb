# frozen_string_literal: true

require_relative "log_subscriber"

module Lepus
  class Railtie < ::Rails::Railtie
    config.lepus = ActiveSupport::OrderedOptions.new
    config.lepus.app_executor = nil
    config.lepus.on_thread_error = nil

    initializer "lepus.app_executor", before: :run_prepare_callbacks do |app|
      config.lepus.app_executor ||= app.executor
      if ::Rails.respond_to?(:error) && config.lepus.on_thread_error.nil?
        config.lepus.on_thread_error = ->(exception) { ::Rails.error.report(exception, handled: false) }
      elsif config.lepus.on_thread_error.nil?
        config.lepus.on_thread_error = ->(exception) { Lepus.logger.error(exception) }
      end

      Lepus.config.app_executor = config.lepus.app_executor
      Lepus.config.on_thread_error = config.lepus.on_thread_error
    end

    initializer "lepus.logger" do
      ActiveSupport.on_load(:lepus) do
        self.logger = ::Rails.logger if logger == Lepus::DEFAULT_LOGGER
      end

      Lepus::LogSubscriber.attach_to :lepus
    end
  end

  ActiveSupport.run_load_hooks(:lepus, self)
end
