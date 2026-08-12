# frozen_string_literal: true

module Btape
  # The duration literals .tape scripts use ("500ms", "1.5s"). The parser,
  # the runner and Settings all need the same format, so it lives here once
  # rather than as a regexp repeated at each call site.
  module Duration
    PATTERN = /\A(\d+(?:\.\d+)?)(ms|s)\z/
    DESCRIPTION = 'must use ms or s (for example, 500ms or 1.5s)'

    module_function

    def valid?(value)
      PATTERN.match?(value.to_s)
    end

    # Returns the duration in seconds.
    def parse(value)
      match = PATTERN.match(value.to_s)
      raise ArgumentError, "duration #{DESCRIPTION}" unless match

      amount, unit = match.captures
      amount.to_f / (unit == 'ms' ? 1000 : 1)
    end
  end
end
