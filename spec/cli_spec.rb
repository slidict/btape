# frozen_string_literal: true

require_relative 'spec_helper'
require 'stringio'
require 'tmpdir'

RSpec.describe Btape::CLI do
  let(:fake_runner_class) do
    Struct.new(:received) do
      def run(commands, base_directory:)
        self.received = [commands, base_directory]
        File.join(base_directory, 'demo.gif')
      end
    end
  end

  it 'parses and runs a tape' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'demo.tape')
      File.write(path, "Output demo.gif\n")
      runner = fake_runner_class.new
      output = StringIO.new

      status = described_class.new(out: output, err: StringIO.new, runner: runner).run([path])

      expect(status).to eq(0)
      expect(runner.received.last).to eq(directory)
      expect(output.string).to include('Created')
    end
  end

  it 'prints help and lists commands when given no arguments' do
    output = StringIO.new

    status = described_class.new(out: output, err: StringIO.new).run([])

    expect(status).to eq(0)
    expect(output.string).to match(/^Commands:$/)
  end

  it 'prints help for the help command' do
    output = StringIO.new

    status = described_class.new(out: output, err: StringIO.new).run(['help'])

    expect(status).to eq(0)
    expect(output.string).to match(/^Commands:$/)
  end
end
