# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in lepus.gemspec
gemspec

gem "connection_pool", "< 3"

# prometheus_exporter 2.1.1+ requires Ruby 3.0+; 2.3+ requires Ruby 3.2+.
# The CI matrix runs this Gemfile on Ruby 2.7 and 3.0, so pin to a version
# compatible across the matrix.
gem "prometheus_exporter", "= 2.1.0"
