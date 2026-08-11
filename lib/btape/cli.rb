# frozen_string_literal: true

require 'optparse'

module Btape
  # Entry point invoked by the `btape` executable: parses argv, runs the
  # script, and reports success or failure.
  class CLI
    Options = Struct.new(:help, :settings)

    USAGE = 'Usage: btape [options] SCRIPT.tape'
    HELP_ARGUMENTS = %w[help -h --help].freeze
    HELP_COMMANDS = ['Output PATH', 'Viewport WIDTHxHEIGHT', 'Goto URL', 'Click SELECTOR',
                     'Type SELECTOR TEXT', 'Sleep DURATION', 'Set NAME VALUE'].freeze

    def initialize(out: $stdout, err: $stderr, runner: Runner.new)
      @out = out
      @err = err
      @runner = runner
    end

    def run(argv)
      options = Options.new(false, {})
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

    def record(argument, options)
      script = File.expand_path(argument)
      commands = Parser.new.parse(File.read(script))
      output = @runner.run(commands, base_directory: File.dirname(script), settings: settings(options))
      @out.puts "Created #{output}"
    end

    # The tape's own `Set` lines are the baseline; these flags override them,
    # which is what lets one tape run against a local and a remote browser.
    def settings(options)
      options.settings.merge(ws_url: options.settings[:ws_url] || ENV.fetch('BTAPE_WS_URL', nil))
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
        parser.on('-h', '--help', 'Show this message') { options.help = true }
      end
    end

    def print_help
      @out.puts USAGE
      @out.puts
      @out.puts 'Options:'
      @out.puts '  --ws-url URL     Connect to a browser already running at this CDP url'
      @out.puts '  --set NAME=VALUE Override a setting, as a Set line would'
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
