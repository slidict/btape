# frozen_string_literal: true

module Btape
  class Error < StandardError; end

  # Raised when a run outlasts Set Timeout. A page that never finishes
  # loading would otherwise record until the disk filled.
  class TimeoutError < Error; end

  # Raised for a problem in the .tape script itself, carrying the line
  # number so the CLI can report where the script went wrong.
  class ScriptError < Error
    attr_reader :line_number

    def initialize(line_number, message)
      @line_number = line_number
      super("line #{line_number}: #{message}")
    end
  end
end
