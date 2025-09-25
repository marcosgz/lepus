# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "lepus"
require "lepus/web"

run Lepus::Web::App.build
