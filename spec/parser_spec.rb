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
end
