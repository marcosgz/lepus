# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "lepus"
require "lepus/web"

# Start web services for real data
Lepus::Web.start

# Graceful shutdown
at_exit { Lepus::Web.stop }

run Lepus::Web::App.build
