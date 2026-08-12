# frozen_string_literal: true

require 'logger'
require 'optparse'
require_relative 'generate_command'
require_relative 'parser'

module Btape
  # Entry point invoked by the `btape` executable: parses argv, runs the
  # script, and reports success or failure.
  class CLI
    Options = Struct.new(:help, :settings, :frames_directory, :verbose)

    USAGE = 'Usage: btape [options] SCRIPT.tape'
    HELP_ARGUMENTS = %w[help -h --help].freeze
    HELP_COMMANDS = Parser::SIGNATURES.map { |name, arguments| "#{name} #{arguments}".strip }.freeze
    GENERATE = 'generate'
    # The two ways a flag can name a browser: --ws-url and --set WsUrl=.
    WS_URL_KEYS = [:ws_url, 'WsUrl'].freeze

    # The runner is built after the flags are read, so that --verbose can
    # reach it. Pass one to use it as given.
    def initialize(out: $stdout, err: $stderr, stdin: $stdin, runner: nil, generator: nil)
      @out = out
      @err = err
      @stdin = stdin
      @runner = runner
      @generator = generator
    end

    def run(argv)
      return generate(argv.drop(1)) if argv.first == GENERATE

      options = Options.new(false, {}, nil, false)
      arguments = parse_options(argv, options)
      return print_help if options.help || arguments.empty? || HELP_ARGUMENTS.include?(arguments.first)
      raise Error, USAGE unless arguments.length == 1

      record(arguments.first, options)
      0
    rescue Error, SystemCallError => e
      @err.puts "btape: #{e.message}"
      1
    end

    private

    def generate(argv)
      GenerateCommand.new(out: @out, err: @err, stdin: @stdin, generator: @generator).run(argv)
    end

    def record(argument, options)
      script = File.expand_path(argument)
      commands = Parser.new.parse(read_script(script))
      result = runner(options).run(
        commands,
        base_directory: File.dirname(script),
        settings: settings(options),
        frames_directory: options.frames_directory
      )
      @out.puts "Created #{result.output_path}"
      report_frames(result)
    end

    # Tapes are UTF-8, not whatever the locale happens to be. A tape that
    # types text or matches on it is as likely to be written in Japanese or
    # Greek as in ASCII, and read through the default external encoding a
    # machine with LANG unset would reject those bytes while parsing rather
    # than while recording.
    def read_script(path)
      File.read(path, encoding: Encoding::UTF_8)
    end

    def runner(options)
      @runner || Runner.new(logger: logger(options))
    end

    def logger(options)
      return NullLogger.new unless options.verbose

      Logger.new(@err, level: Logger::DEBUG, formatter: ->(_severity, _time, _program, message) { "#{message}\n" })
    end

    def report_frames(result)
      return if result.frame_paths.empty?

      @out.puts "Kept #{result.frame_paths.length} frame(s) in #{File.dirname(result.frame_paths.first)}"
    end

    # The tape's own `Set` lines are the baseline; these flags override them,
    # which is what lets one tape run against a local and a remote browser.
    #
    # BTAPE_WS_URL is the last resort, and only applies when neither flag named
    # a browser. Settings resolves --ws-url and --set WsUrl to the same
    # attribute, so merging the environment in unconditionally would let it
    # overwrite the --set value rather than fall back to it.
    def settings(options)
      return options.settings if WS_URL_KEYS.any? { |key| options.settings.key?(key) }

      options.settings.merge(ws_url: ENV.fetch('BTAPE_WS_URL', nil))
    end

    def parse_options(argv, options)
      option_parser(options).parse(argv)
    rescue OptionParser::ParseError => e
      raise Error, e.message
    end

    def option_parser(options)
      OptionParser.new do |parser|
        parser.banner = USAGE
        parser.on('--ws-url URL', 'Connect to a browser already running at this CDP url') do |url|
          options.settings[:ws_url] = url
        end
        parser.on('--set NAME=VALUE', 'Override a setting, as a Set line would') do |pair|
          name, value = pair.split('=', 2)
          raise Error, '--set expects NAME=VALUE' if value.nil?

          options.settings[name] = value
        end
        parser.on('--frames-dir DIR', 'Write the PNG frames here and keep them') do |directory|
          options.frames_directory = directory
        end
        parser.on('--verbose', 'Report each command on stderr as it runs') { options.verbose = true }
        parser.on('-h', '--help', 'Show this message') { options.help = true }
      end
    end

    def print_help
      @out.puts USAGE
      @out.puts
      @out.puts 'Options:'
      @out.puts '  --ws-url URL     Connect to a browser already running at this CDP url'
      @out.puts '  --set NAME=VALUE Override a setting, as a Set line would'
      @out.puts '  --frames-dir DIR Write the PNG frames here and keep them'
      @out.puts '  --verbose        Report each command on stderr as it runs'
      @out.puts
      @out.puts 'Subcommands:'
      @out.puts '  generate DESCRIPTION  Write a tape by asking a local model; btape generate --help'
      @out.puts
      @out.puts 'Commands:'
      HELP_COMMANDS.each { |command| @out.puts "  #{command}" }
      @out.puts
      @out.puts 'Settings:'
      Settings::DEFINITIONS.each_key { |name| @out.puts "  #{name}" }
      0
    end
  end
end
