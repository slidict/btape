# frozen_string_literal: true

require 'shellwords'
require_relative 'duration'
require_relative 'recorder'
require_relative 'settings'

module Btape
  Command = Struct.new(:name, :arguments, :line_number, keyword_init: true)

  # Parses .tape scripts into a list of Command structs, raising ScriptError
  # for unknown commands, wrong argument counts, or invalid argument values.
  class Parser
    # An arity is either an exact count or a range, for commands whose last
    # argument is optional.
    ARITY = {
      'Output' => 1, 'Viewport' => 1, 'Goto' => 1, 'Click' => 1, 'Type' => 2, 'Sleep' => 1,
      'Set' => 2, 'Screenshot' => 0..1, 'Evaluate' => 1, 'WaitFor' => 1..2, 'WaitForJS' => 1..2,
      'Frame' => 1, 'Press' => 1..2
    }.freeze

    # The same commands as they read to somebody being told about them, which
    # is what `btape help` prints and what a model is handed before it is
    # asked for a tape. ARITY is what a script is held to; a spec keeps the
    # two lists from drifting apart.
    SIGNATURES = {
      'Output' => 'PATH', 'Viewport' => 'WIDTHxHEIGHT', 'Goto' => 'URL', 'Click' => 'SELECTOR',
      'Type' => 'SELECTOR TEXT', 'Press' => 'KEY [COUNT]', 'Frame' => 'SELECTOR|main',
      'Evaluate' => 'JAVASCRIPT', 'WaitFor' => 'SELECTOR [TIMEOUT]', 'WaitForJS' => 'JAVASCRIPT [TIMEOUT]',
      'Screenshot' => '[NAME]', 'Sleep' => 'DURATION', 'Set' => 'NAME VALUE'
    }.freeze

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
      unless arity === words.length # rubocop:disable Style/CaseEquality
        raise ScriptError.new(number, "#{name} expects #{arity} argument(s), got #{words.length}")
      end

      validate(name, words, number)
      Command.new(name:, arguments: words.freeze, line_number: number)
    end

    def validate(name, arguments, number)
      case name
      when 'Viewport' then validate_viewport(arguments.first, number)
      when 'Sleep' then validate_sleep(arguments.first, number)
      when 'Set' then Settings.validate!(*arguments)
      when 'Screenshot' then validate_frame_name(arguments.first, number)
      when 'WaitFor', 'WaitForJS' then validate_wait_timeout(name, arguments, number)
      when 'Press' then validate_press_count(arguments[1], number)
      end
    end

    def validate_press_count(value, number)
      return if value.nil? || (/\A\d+\z/.match?(value) && value.to_i.positive?)

      raise ScriptError.new(number, 'Press count must be a positive integer')
    end

    def validate_wait_timeout(name, arguments, number)
      timeout = arguments[1]
      return if timeout.nil? || Duration.valid?(timeout)

      raise ScriptError.new(number, "#{name} timeout #{Duration::DESCRIPTION}")
    end

    # The name becomes part of a filename, so keep it to something that
    # cannot escape the frames directory. Recorder rejects the same names, but
    # catching it here names the line the script has to fix.
    def validate_frame_name(value, number)
      return if value.nil? || Recorder::FRAME_NAME.match?(value)

      raise ScriptError.new(number, 'Screenshot name must be letters, numbers, dashes, dots or underscores')
    end

    def validate_viewport(value, number)
      match = /\A(\d+)x(\d+)\z/.match(value)
      valid = match&.captures&.all? { |part| part.to_i.positive? }
      raise ScriptError.new(number, 'Viewport must be WIDTHxHEIGHT') unless valid
    end

    def validate_sleep(value, number)
      return if Duration.valid?(value)

      raise ScriptError.new(number, "Sleep duration #{Duration::DESCRIPTION}")
    end
  end
end
