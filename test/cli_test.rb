require_relative "test_helper"
require "stringio"
require "tmpdir"

class CliTest < Minitest::Test
  FakeRunner = Struct.new(:received) do
    def run(commands, base_directory:)
      self.received = [commands, base_directory]
      File.join(base_directory, "demo.gif")
    end
  end

  def test_parses_and_runs_a_tape
    Dir.mktmpdir do |directory|
      path = File.join(directory, "demo.tape")
      File.write(path, "Output demo.gif\n")
      runner = FakeRunner.new
      output = StringIO.new

      status = Btape::CLI.new(out: output, err: StringIO.new, runner: runner).run([path])

      assert_equal 0, status
      assert_equal directory, runner.received.last
      assert_includes output.string, "Created"
    end
  end
end

