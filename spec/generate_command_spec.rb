# frozen_string_literal: true

require_relative 'spec_helper'
require 'stringio'
require 'tmpdir'

RSpec.describe Btape::GenerateCommand do
  let(:tape) { "Output demo.gif\nGoto http://localhost:3000\n" }

  let(:fake_generator_class) do
    Struct.new(:tape, :description, :context) do
      def call(description, context: nil)
        self.description = description
        self.context = context
        tape
      end
    end
  end

  def generate(argv, generator: fake_generator_class.new(tape), stdin: StringIO.new)
    out = StringIO.new
    err = StringIO.new
    # Reached through the CLI rather than directly, since that is the path
    # `btape generate` actually takes, error handling included.
    status = Btape::CLI.new(out: out, err: err, stdin: stdin, generator: generator).run(['generate'] + argv)
    yield(status: status, out: out.string, err: err.string, generator: generator)
  end

  it 'writes the tape to standard output' do
    generate(['record the sign-in page']) do |status:, out:, generator:, **|
      expect(status).to eq(0)
      expect(out).to eq(tape)
      expect(generator.description).to eq('record the sign-in page')
    end
  end

  it 'joins the words after the flags into the description' do
    generate(['--temperature', '0.4', 'record', 'the', 'sign-in', 'page']) do |generator:, **|
      expect(generator.description).to eq('record the sign-in page')
    end
  end

  it 'reads the description from standard input when none was given' do
    generate([], stdin: StringIO.new("record the sign-in page\n")) do |status:, generator:, **|
      expect(status).to eq(0)
      expect(generator.description).to eq("record the sign-in page\n")
    end
  end

  it 'writes the tape to the file --out names' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'signin.tape')

      generate(['--out', path, 'record the sign-in page']) do |status:, out:, **|
        expect(status).to eq(0)
        expect(File.read(path)).to eq(tape)
        expect(out).to include("Wrote #{path}")
      end
    end
  end

  it 'passes a --context file to the generator' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'notes.md')
      File.write(path, "the sign-in button is #go\n")

      generate(['--context', path, 'record it']) do |generator:, **|
        expect(generator.context).to include('#go')
      end
    end
  end

  it 'reports a model that could not be reached rather than raising' do
    unreachable = Class.new do
      def call(*, **) = raise(Btape::LLM::Error, 'could not reach a model server')
    end

    generate(['record it'], generator: unreachable.new) do |status:, err:, **|
      expect(status).to eq(1)
      expect(err).to include('btape: could not reach a model server')
    end
  end

  it 'reports an unknown flag' do
    generate(['--sparkles', 'record it']) do |status:, err:, **|
      expect(status).to eq(1)
      expect(err).to include('invalid option')
    end
  end

  it 'prints its own help' do
    generate(['--help']) do |status:, out:, **|
      expect(status).to eq(0)
      expect(out).to include('--llm-url').and include('localhost:11434')
    end
  end

  it 'is offered by the top-level help' do
    out = StringIO.new

    Btape::CLI.new(out: out, err: StringIO.new).run([])

    expect(out.string).to include('generate')
  end
end
