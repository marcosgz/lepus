# frozen_string_literal: true

module Lepus::Processes
  module Procline
    # Sets the procline ($0)
    # [lepus-supervisor: <string>]
    def procline(string)
      $0 = "[lepus-#{kind.downcase}: #{string}]"
    end
  end
end
