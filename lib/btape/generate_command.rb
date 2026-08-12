# frozen_string_literal: true

require 'logger'
require 'optparse'
require_relative 'error'
require_relative 'llm/client'
require_relative 'llm/generator'
require_relative 'null_logger'

module Btape
  # `btape generate` — asks a model running on this machine for a tape and
  # writes it out, having first checked that what came back is one.
  #
  # It is a separate command rather than a flag on a recording because it
  # records nothing: no browser is opened, and the answer is a file to read,
  # edit and then run like any other tape.
  class GenerateCommand
    USAGE = 'Usage: btape generate [options] DESCRIPTION'

    Options = Struct.new(:help, :output_path, :context_path, :client, :verbose, keyword_init: true)

    def initialize(out: $stdout, err: $stderr, stdin: $stdin, generator: nil)
      @out = out
      @err = err
      @stdin = stdin
      @generator = generator
    end

    def run(argv)
      options = Options.new(help: false, client: {}, verbose: false)
      words = parse_options(argv, options)
      return print_help if options.help

      write(generator(options).call(description(words), context: context(options)), options)
      0
    end

    private

    def write(script, options)
      return @out.print(script) unless options.output_path

      path = File.expand_path(options.output_path)
      File.write(path, script, encoding: Encoding::UTF_8)
      @out.puts "Wrote #{path}"
    end

    # The description is the words left after the flags, or standard input
    # when there are none — a paragraph about what to record is easier to
    # write in a file, or to pipe in, than to quote on a command line.
    def description(words)
      return words.join(' ') unless words.empty?
      raise Error, USAGE if @stdin.tty?

      @stdin.read.to_s
    end

    def context(options)
      return nil unless options.context_path

      File.read(File.expand_path(options.context_path), encoding: Encoding::UTF_8)
    end

    def generator(options)
      @generator || LLM::Generator.new(client: LLM::Client.new(**options.client), logger: logger(options))
    end

    def logger(options)
      return NullLogger.new unless options.verbose

      Logger.new(@err, level: Logger::DEBUG, formatter: ->(_severity, _time, _program, message) { "#{message}\n" })
    end

    def parse_options(argv, options)
      option_parser(options).parse(argv)
    rescue OptionParser::ParseError => e
      raise Error, e.message
    end

    def option_parser(options)
      OptionParser.new do |parser|
        parser.banner = USAGE
        parser.on('--llm-url URL', 'The OpenAI-compatible model server to ask') do |url|
          options.client[:base_url] = url
        end
        parser.on('--model NAME', 'Ask for this model rather than whichever one is loaded') do |name|
          options.client[:model] = name
        end
        parser.on('--temperature N', Float, 'How freely the model writes; 0.2 by default') do |value|
          options.client[:temperature] = value
        end
        parser.on('--context FILE', 'Give the model this file as context: selectors, notes, markup') do |path|
          options.context_path = path
        end
        parser.on('-o', '--out FILE', 'Write the tape here rather than to standard output') do |path|
          options.output_path = path
        end
        parser.on('--verbose', 'Report each attempt on stderr') { options.verbose = true }
        parser.on('-h', '--help', 'Show this message') { options.help = true }
      end
    end

    def print_help
      @out.puts USAGE
      @out.puts
      @out.puts 'Options:'
      @out.puts '  --llm-url URL    The OpenAI-compatible model server to ask'
      @out.puts '  --model NAME     Ask for this model rather than whichever one is loaded'
      @out.puts '  --temperature N  How freely the model writes; 0.2 by default'
      @out.puts '  --context FILE   Give the model this file as context: selectors, notes, markup'
      @out.puts '  -o, --out FILE   Write the tape here rather than to standard output'
      @out.puts '  --verbose        Report each attempt on stderr'
      @out.puts
      @out.puts "Defaults to #{LLM::Client::DEFAULT_BASE_URL}, which is where LM Studio serves."
      @out.puts 'Ollama serves the same API at http://localhost:11434/v1.'
      @out.puts 'BTAPE_LLM_URL, BTAPE_LLM_MODEL and BTAPE_LLM_KEY are used when the flags are not given.'
      0
    end
  end
end
