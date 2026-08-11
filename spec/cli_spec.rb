require_relative "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe Btape::CLI do
  FakeRunner = Struct.new(:received) do
    def run(commands, base_directory:)
      self.received = [commands, base_directory]
      File.join(base_directory, "demo.gif")
    end
  end

  it "parses and runs a tape" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "demo.tape")
      File.write(path, "Output demo.gif\n")
      runner = FakeRunner.new
      output = StringIO.new

      status = described_class.new(out: output, err: StringIO.new, runner: runner).run([path])

      expect(status).to eq(0)
      expect(runner.received.last).to eq(directory)
      expect(output.string).to include("Created")
    end
  end
end
