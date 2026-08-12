# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Btape::Parser do
  it 'parses the mvp commands and quoted arguments' do
    commands = described_class.new.parse(<<~TAPE)
      # a comment
      Output demo.gif
      Viewport 1280x720
      Goto http://localhost:3000
      Click "text=Log in"
      Type "#email" "demo@example.com"
      Sleep 500ms
    TAPE

    expect(commands.map(&:name)).to eq(%w[Output Viewport Goto Click Type Sleep])
    expect(commands[4].arguments).to eq(['#email', 'demo@example.com'])
    expect(commands[3].line_number).to eq(5)
  end

  it 'reports unknown command with its line number' do
    expect { described_class.new.parse("\nDance now\n") }
      .to raise_error(Btape::ScriptError, 'line 2: unknown command "Dance"')
  end

  it 'validates arguments' do
    expect { described_class.new.parse("Sleep tomorrow\n") }
      .to raise_error(Btape::ScriptError, /line 1: Sleep duration/)
  end

  it 'parses Set lines' do
    commands = described_class.new.parse("Set CaptureMode manual\n")

    expect(commands.first.arguments).to eq(%w[CaptureMode manual])
  end

  it 'rejects an unknown setting with its line number' do
    expect { described_class.new.parse("Output demo.gif\nSet Sparkles yes\n") }
      .to raise_error(Btape::ScriptError, 'line 2: unknown setting "Sparkles"')
  end

  it 'accepts Screenshot with and without a name' do
    commands = described_class.new.parse("Screenshot\nScreenshot cover\n")

    expect(commands.map(&:arguments)).to eq([[], ['cover']])
  end

  it 'rejects a Screenshot name that could escape the frames directory' do
    expect { described_class.new.parse("Screenshot ../etc/passwd\n") }
      .to raise_error(Btape::ScriptError, /line 1: Screenshot name/)
  end

  it 'rejects a Press count that is not a positive integer' do
    expect { described_class.new.parse("Press Right twice\n") }
      .to raise_error(Btape::ScriptError, 'line 1: Press count must be a positive integer')
  end

  it 'rejects a wait timeout that is not a duration' do
    expect { described_class.new.parse("WaitForJS window.READY 10\n") }
      .to raise_error(Btape::ScriptError, /line 1: WaitForJS timeout/)
  end

  it 'reports the wrong number of arguments' do
    expect { described_class.new.parse("Set CaptureMode\n") }
      .to raise_error(Btape::ScriptError, 'line 1: Set expects 2 argument(s), got 1')
  end

  # Help and the prompt a model is given both quote SIGNATURES, so a command
  # added to ARITY and nowhere else would be a command nobody is told about.
  it 'describes every command it accepts, and no others' do
    expect(described_class::SIGNATURES.keys).to match_array(described_class::ARITY.keys)
  end

  # A signature names one argument per word, and brackets the ones the arity
  # lets a script leave out — so counting both halves catches a signature
  # that gained or lost an argument the parser does not agree about.
  it 'names as many arguments as the arity allows, bracketing the optional ones' do
    described_class::SIGNATURES.each do |name, signature|
      words = signature.split
      arity = described_class::ARITY.fetch(name)
      allowed = arity.is_a?(Range) ? arity : (arity..arity)

      expect(words.reject { |word| word.start_with?('[') }.length).to eq(allowed.min), "#{name} #{signature}"
      expect(words.length).to eq(allowed.max), "#{name} #{signature}"
    end
  end
end
