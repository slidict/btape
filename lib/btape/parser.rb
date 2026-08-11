# frozen_string_literal: true

require 'shellwords'

module Btape
  Command = Struct.new(:name, :arguments, :line_number, keyword_init: true)

  # Parses .tape scripts into a list of Command structs, raising ScriptError
  # for unknown commands, wrong argument counts, or invalid argument values.
  class Parser
    ARITY = { 'Output' => 1, 'Viewport' => 1, 'Goto' => 1, 'Click' => 1, 'Type' => 2, 'Sleep' => 1 }.freeze

    def parse(source)
      source.each_line.with_index(1).filter_map do |line, number|
        text = line.strip
        next if text.empty? || text.start_with?('#')

        parse_line(text, number)
      rescue ArgumentError => e
        raise ScriptError.new(number, e.message)
      end
    end

    private

    def parse_line(text, number)
      words = Shellwords.shellsplit(text)
      name = words.shift
      raise ScriptError.new(number, "unknown command #{name.inspect}") unless ARITY.key?(name)

      arity = ARITY.fetch(name)
      unless words.length == arity
        raise ScriptError.new(number, "#{name} expects #{arity} argument(s), got #{words.length}")
      end

      validate(name, words, number)
      Command.new(name:, arguments: words.freeze, line_number: number)
    end

    def validate(name, arguments, number)
      case name
      when 'Viewport' then validate_viewport(arguments.first, number)
      when 'Sleep' then validate_sleep(arguments.first, number)
      end
    end

    def validate_viewport(value, number)
      match = /\A(\d+)x(\d+)\z/.match(value)
      valid = match&.captures&.all? { |part| part.to_i.positive? }
      raise ScriptError.new(number, 'Viewport must be WIDTHxHEIGHT') unless valid
    end

    def validate_sleep(value, number)
      return if /\A(\d+(?:\.\d+)?)(ms|s)\z/.match?(value)

      raise ScriptError.new(number, 'Sleep duration must use ms or s (for example, 500ms or 1.5s)')
    end
  end
end
