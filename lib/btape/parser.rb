require "shellwords"

module Btape
  Command = Struct.new(:name, :arguments, :line_number, keyword_init: true)

  class Parser
    ARITY = { "Output" => 1, "Viewport" => 1, "Goto" => 1, "Click" => 1, "Type" => 2, "Sleep" => 1 }.freeze

    def parse(source)
      source.each_line.with_index(1).filter_map do |line, number|
        text = line.strip
        next if text.empty? || text.start_with?("#")

        words = Shellwords.shellsplit(text)
        name = words.shift
        raise ScriptError.new(number, "unknown command #{name.inspect}") unless ARITY.key?(name)
        raise ScriptError.new(number, "#{name} expects #{ARITY.fetch(name)} argument(s), got #{words.length}") unless words.length == ARITY.fetch(name)

        validate(name, words, number)
        Command.new(name:, arguments: words.freeze, line_number: number)
      rescue ArgumentError => e
        raise ScriptError.new(number, e.message)
      end
    end

    private

    def validate(name, arguments, number)
      case name
      when "Viewport"
        match = /\A(\d+)x(\d+)\z/.match(arguments.first)
        raise ScriptError.new(number, "Viewport must be WIDTHxHEIGHT") unless match && match.captures.all? { |value| value.to_i.positive? }
      when "Sleep"
        match = /\A(\d+(?:\.\d+)?)(ms|s)\z/.match(arguments.first)
        raise ScriptError.new(number, "Sleep duration must use ms or s (for example, 500ms or 1.5s)") unless match
      end
    end
  end
end

