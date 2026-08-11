# frozen_string_literal: true

require_relative 'duration'

module Btape
  # The knobs a script turns with `Set NAME VALUE`, along with their defaults,
  # their coercions, and the validation the parser calls while reading a tape.
  #
  # Values arrive from three places, in increasing order of precedence: the
  # defaults here, the `Set` lines in the tape, and whatever the caller passes
  # to Runner#run or the CLI passes from its flags.
  class Settings
    CAPTURE_MODES = %w[interval manual].freeze
    QUANTIZERS = %w[adaptive rgb332].freeze
    URL_SCHEMES = %w[ws:// wss:// http:// https://].freeze

    # Script name => [attribute, coercion, default]. Defaults are already
    # coerced, so durations are seconds and not "100ms".
    DEFINITIONS = {
      'WsUrl' => [:ws_url, :url, nil],
      'CaptureMode' => [:capture_mode, CAPTURE_MODES, 'interval'],
      'Framerate' => [:framerate, :positive_float, 10.0],
      'FrameDelay' => [:frame_delay, :duration, 0.1],
      'Loop' => [:loop_count, :count, 0],
      'Scale' => [:scale, :positive_float, 1.0],
      'OutputWidth' => [:output_width, :positive_integer, nil],
      'Quantizer' => [:quantizer, QUANTIZERS, 'adaptive'],
      'Timeout' => [:timeout, :duration, 120.0],
      'WaitTimeout' => [:wait_timeout, :duration, 10.0],
      'WaitInterval' => [:wait_interval, :duration, 0.1],
      'WaitStable' => [:wait_stable, :positive_integer, 1],
      'MaxFrames' => [:max_frames, :positive_integer, 600]
    }.freeze

    ATTRIBUTES = DEFINITIONS.each_value.map(&:first).freeze

    ATTRIBUTES.each { |attribute| define_method(attribute) { @values.fetch(attribute) } }

    class << self
      def defaults
        DEFINITIONS.each_value.to_h { |attribute, _coercion, default| [attribute, default] }
      end

      # Validates one `Set` line and returns the coerced value. Raises
      # ArgumentError, which Parser turns into a ScriptError carrying the line.
      def validate!(name, value)
        attribute, coercion, = DEFINITIONS.fetch(name) { raise ArgumentError, "unknown setting #{name.inspect}" }
        [attribute, coerce(coercion, value, name)]
      end

      def from_commands(commands)
        values = commands.select { |command| command.name == 'Set' }.to_h do |command|
          validate!(*command.arguments)
        rescue ArgumentError => e
          raise ScriptError.new(command.line_number, e.message)
        end
        new(values)
      end

      private

      def coerce(coercion, value, name)
        return enum(coercion, value, name) if coercion.is_a?(Array)

        case coercion
        when :duration then duration(value, name)
        when :url then url(value, name)
        when :count then integer(value, name, minimum: 0)
        when :positive_integer then integer(value, name, minimum: 1)
        when :positive_float then positive_float(value, name)
        end
      end

      def enum(allowed, value, name)
        return value if allowed.include?(value)

        raise ArgumentError, "Set #{name} must be one of #{allowed.join(', ')}"
      end

      def duration(value, name)
        raise ArgumentError, "Set #{name} #{Duration::DESCRIPTION}" unless Duration.valid?(value)

        Duration.parse(value)
      end

      def url(value, name)
        return value if URL_SCHEMES.any? { |scheme| value.start_with?(scheme) }

        raise ArgumentError, "Set #{name} must start with #{URL_SCHEMES.join(', ')}"
      end

      def integer(value, name, minimum:)
        number = Integer(value, 10) if /\A\d+\z/.match?(value)
        raise ArgumentError, "Set #{name} must be an integer of at least #{minimum}" if number.nil? || number < minimum

        number
      end

      def positive_float(value, name)
        number = Float(value) if /\A\d+(?:\.\d+)?\z/.match?(value)
        raise ArgumentError, "Set #{name} must be a positive number" unless number&.positive?

        number
      end
    end

    def initialize(values = {})
      @values = defaults_merged_with(values).freeze
      freeze
    end

    def merge(overrides)
      return self if overrides.nil? || (overrides.respond_to?(:empty?) && overrides.empty?)

      self.class.new(@values.merge(normalize(overrides)))
    end

    def to_h
      @values.dup
    end

    private

    def defaults_merged_with(values)
      values.is_a?(Settings) ? values.to_h : self.class.defaults.merge(normalize(values))
    end

    # Symbol keys are attributes the caller has already coerced (`frame_delay:
    # 0.15`); String keys are script names that go through the same validation
    # a `Set` line would. nil values are dropped so callers can pass unset
    # flags straight through.
    def normalize(values)
      values.to_h.compact.to_h do |key, value|
        next self.class.validate!(key, value) if key.is_a?(String)
        raise Error, "unknown setting #{key.inspect}" unless ATTRIBUTES.include?(key)

        [key, value]
      end
    rescue ArgumentError => e
      raise Error, e.message
    end
  end
end
