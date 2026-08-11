# frozen_string_literal: true

module Btape
  # Stands in when no logger was given, so the rest of the code can log
  # unconditionally. Only the three levels btape uses are defined, and any
  # Logger — Rails' included — can be passed instead.
  class NullLogger
    def debug(*); end

    def info(*); end

    def warn(*); end
  end
end
