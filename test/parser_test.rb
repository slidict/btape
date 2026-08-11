require_relative "test_helper"

class ParserTest < Minitest::Test
  def test_parses_the_mvp_commands_and_quoted_arguments
    commands = Btape::Parser.new.parse(<<~TAPE)
      # a comment
      Output demo.gif
      Viewport 1280x720
      Goto http://localhost:3000
      Click "text=Log in"
      Type "#email" "demo@example.com"
      Sleep 500ms
    TAPE

    assert_equal %w[Output Viewport Goto Click Type Sleep], commands.map(&:name)
    assert_equal ["#email", "demo@example.com"], commands[4].arguments
    assert_equal 5, commands[3].line_number
  end

  def test_reports_unknown_command_with_its_line_number
    error = assert_raises(Btape::ScriptError) { Btape::Parser.new.parse("\nDance now\n") }

    assert_equal "line 2: unknown command \"Dance\"", error.message
  end

  def test_validates_arguments
    error = assert_raises(Btape::ScriptError) { Btape::Parser.new.parse("Sleep tomorrow\n") }

    assert_match(/line 1: Sleep duration/, error.message)
  end
end

