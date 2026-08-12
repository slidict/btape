# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Btape::Settings do
  def set_command(name, value, line_number: 1)
    Btape::Command.new(name: 'Set', arguments: [name, value], line_number: line_number)
  end

  it 'falls back to the documented defaults' do
    settings = described_class.new

    expect(settings.ws_url).to be_nil
    expect(settings.capture_mode).to eq('interval')
    expect(settings.framerate).to eq(10.0)
    expect(settings.frame_delay).to eq(0.1)
    expect(settings.timeout).to eq(120.0)
    expect(settings.max_frames).to eq(600)
  end

  it 'folds Set commands into coerced values' do
    settings = described_class.from_commands(
      [
        set_command('WsUrl', 'ws://chrome:3000'),
        set_command('CaptureMode', 'manual'),
        set_command('FrameDelay', '250ms'),
        set_command('WaitStable', '5')
      ]
    )

    expect(settings.ws_url).to eq('ws://chrome:3000')
    expect(settings.capture_mode).to eq('manual')
    expect(settings.frame_delay).to eq(0.25)
    expect(settings.wait_stable).to eq(5)
  end

  it 'lets the caller override what the tape set' do
    settings = described_class.from_commands([set_command('WsUrl', 'ws://from-tape:3000')])

    expect(settings.merge(ws_url: 'ws://from-caller:3000').ws_url).to eq('ws://from-caller:3000')
  end

  it 'ignores nil overrides so unset flags can be passed straight through' do
    settings = described_class.from_commands([set_command('WsUrl', 'ws://chrome:3000')])

    expect(settings.merge(ws_url: nil, capture_mode: 'manual').ws_url).to eq('ws://chrome:3000')
  end

  it 'coerces string keyed overrides the same way a Set line is coerced' do
    expect(described_class.new.merge('FrameDelay' => '2s').frame_delay).to eq(2.0)
  end

  it 'reports an unknown setting with the line it came from' do
    expect { described_class.from_commands([set_command('Sparkles', 'yes', line_number: 4)]) }
      .to raise_error(Btape::ScriptError, 'line 4: unknown setting "Sparkles"')
  end

  it 'rejects a value outside an enumerated setting' do
    expect { described_class.validate!('CaptureMode', 'whenever') }
      .to raise_error(ArgumentError, 'Set CaptureMode must be one of interval, manual')
  end

  it 'rejects a ws url without a supported scheme' do
    expect { described_class.validate!('WsUrl', 'chrome:3000') }
      .to raise_error(ArgumentError, %r{must start with ws://})
  end

  it 'rejects a non-positive count' do
    expect { described_class.validate!('WaitStable', '0') }
      .to raise_error(ArgumentError, 'Set WaitStable must be an integer of at least 1')
  end

  it 'allows Loop to be zero, meaning forever' do
    expect(described_class.validate!('Loop', '0')).to eq([:loop_count, 0])
  end

  it 'reads a string keyed override that is not a String' do
    expect(described_class.new.merge('Loop' => 3).loop_count).to eq(3)
  end

  it 'reports a string keyed override of the wrong type as a setting error' do
    expect { described_class.new.merge('WsUrl' => 3000) }
      .to raise_error(Btape::Error, %r{must start with ws://})
  end
end
