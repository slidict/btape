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

    def run(argv)
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
  end
end
