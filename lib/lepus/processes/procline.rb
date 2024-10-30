# frozen_string_literal: true

module Lepus::Processes
  module Procline
    # Sets the procline ($0)
    # lepus-supervisor(0.1.0): <string>
    def procline(string)
      $0 = "lepus-#{self.class.name.split("::").last.downcase}: #{string}"
    end
  end
end
