# frozen_string_literal: true

require "rails/railtie"
require "active_support/log_subscriber"

module Lepus
  module Rails
  end
end

require_relative "rails/log_subscriber"
require_relative "rails/railtie"
