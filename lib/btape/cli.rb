# frozen_string_literal: true

module Btape
  # Entry point invoked by the `btape` executable: parses argv, runs the
  # script, and reports success or failure.
  class CLI
    def initialize(out: $stdout, err: $stderr, runner: Runner.new)
      @out = out
      @err = err
      @runner = runner
    end

    HELP_COMMANDS = ['Output PATH', 'Viewport WIDTHxHEIGHT', 'Goto URL', 'Click SELECTOR',
                     'Type SELECTOR TEXT', 'Sleep DURATION'].freeze

    def run(argv)
      return print_help if argv.empty? || %w[help -h --help].include?(argv.first)
      raise Error, 'usage: btape SCRIPT.tape' unless argv.length == 1

      script = File.expand_path(argv.first)
      commands = Parser.new.parse(File.read(script))
      output = @runner.run(commands, base_directory: File.dirname(script))
      @out.puts "Created #{output}"
      0
    rescue Error, SystemCallError => e
      @err.puts "btape: #{e.message}"
      1
    end

    private

    def print_help
      @out.puts 'Usage: btape SCRIPT.tape'
      @out.puts
      @out.puts 'Commands:'
      HELP_COMMANDS.each { |command| @out.puts "  #{command}" }
      0
    end
  end
end
