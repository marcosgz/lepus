# frozen_string_literal: true

module Lepus
  module AppExecutor
    def wrap_in_app_executor(&block)
      if Lepus.config.app_executor
        Lepus.config.app_executor.wrap(&block)
      else
        yield
      end
    end

    def handle_thread_error(error)
      Lepus.instrument(:thread_error, error: error)

      Lepus.config.on_thread_error&.call(error)
    end
  end
end
