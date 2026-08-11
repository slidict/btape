module Btape
  class Error < StandardError; end

  class ScriptError < Error
    attr_reader :line_number

    def initialize(line_number, message)
      @line_number = line_number
      super("line #{line_number}: #{message}")
    end
  end
end

