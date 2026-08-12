# frozen_string_literal: true

require_relative 'spec_helper'
require 'stringio'
require 'tmpdir'

RSpec.describe Btape::CLI do
  let(:fake_runner_class) do
    Struct.new(:commands, :base_directory, :settings, :frames_directory) do
      def run(commands, base_directory:, settings: {}, frames_directory: nil, **)
        self.commands = commands
        self.base_directory = base_directory
        self.settings = settings
        self.frames_directory = frames_directory
        Btape::Result.new(
          output_path: File.join(base_directory, 'demo.gif'),
          frame_paths: frames_directory ? [File.join(frames_directory, 'frame-000000.png')] : [],
          frame_count: 1, width: 1280, height: 720
        )
      end
    end
  end

  def run_tape(argv_prefix: [], tape: "Output demo.gif\n", runner: fake_runner_class.new, env: {})
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'demo.tape')
      File.write(path, tape)
      output = StringIO.new
      error = StringIO.new
      status = with_env(env) do
        described_class.new(out: output, err: error, runner: runner).run(argv_prefix + [path])
      end
      yield(status: status, out: output.string, err: error.string, runner: runner, directory: directory)
    end
  end

  def with_default_external(encoding)
    previous = Encoding.default_external
    # Assigning it warns, which says nothing a reader of this spec does not
    # already know from the line above.
    original_verbose = $VERBOSE
    $VERBOSE = nil
    Encoding.default_external = encoding
    yield
  ensure
    Encoding.default_external = previous
    $VERBOSE = original_verbose
  end

  def with_env(env)
    previous = env.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    env.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it 'parses and runs a tape' do
    run_tape do |status:, out:, runner:, directory:, **|
      expect(status).to eq(0)
      expect(runner.base_directory).to eq(directory)
      expect(out).to include('Created')
    end
  end

  # A tape is as likely to type Japanese or Greek as ASCII, and the locale of
  # the machine recording it does not get a say in whether that parses.
  it 'reads a tape as UTF-8 whatever the locale says' do
    with_default_external(Encoding::US_ASCII) do
      run_tape(tape: %(Output demo.gif\nType "#email" "ゆーざー@example.com"\n)) do |status:, err:, runner:, **|
        expect(err).to eq('')
        expect(status).to eq(0)
        expect(runner.commands.last.arguments).to eq(['#email', 'ゆーざー@example.com'])
      end
    end
  end

  it 'passes --ws-url through as a settings override' do
    run_tape(argv_prefix: ['--ws-url', 'ws://chrome:3000']) do |status:, runner:, **|
      expect(status).to eq(0)
      expect(runner.settings[:ws_url]).to eq('ws://chrome:3000')
    end
  end

  it 'falls back to BTAPE_WS_URL when no flag is given' do
    run_tape(env: { 'BTAPE_WS_URL' => 'ws://from-env:3000' }) do |runner:, **|
      expect(runner.settings[:ws_url]).to eq('ws://from-env:3000')
    end
  end

  it 'prefers the flag over BTAPE_WS_URL' do
    run_tape(argv_prefix: ['--ws-url', 'ws://from-flag:3000'], env: { 'BTAPE_WS_URL' => 'ws://from-env:3000' }) do |runner:, **| # rubocop:disable Layout/LineLength
      expect(runner.settings[:ws_url]).to eq('ws://from-flag:3000')
    end
  end

  it 'prefers --set WsUrl over BTAPE_WS_URL' do
    run_tape(argv_prefix: ['--set', 'WsUrl=ws://from-set:3000'], env: { 'BTAPE_WS_URL' => 'ws://from-env:3000' }) do |runner:, **| # rubocop:disable Layout/LineLength
      expect(Btape::Settings.new.merge(runner.settings).ws_url).to eq('ws://from-set:3000')
    end
  end

  it 'passes --set through by its script name' do
    run_tape(argv_prefix: ['--set', 'CaptureMode=manual']) do |runner:, **|
      expect(runner.settings['CaptureMode']).to eq('manual')
    end
  end

  it 'reports a --set without a value' do
    run_tape(argv_prefix: ['--set', 'CaptureMode']) do |status:, err:, **|
      expect(status).to eq(1)
      expect(err).to include('--set expects NAME=VALUE')
    end
  end

  it 'passes --frames-dir through and reports the frames it kept' do
    run_tape(argv_prefix: ['--frames-dir', '/tmp/btape-frames']) do |status:, out:, runner:, **|
      expect(status).to eq(0)
      expect(runner.frames_directory).to eq('/tmp/btape-frames')
      expect(out).to include('Kept 1 frame(s) in /tmp/btape-frames')
    end
  end

  it 'says nothing about frames when none were kept' do
    run_tape do |out:, **|
      expect(out).not_to include('Kept')
    end
  end

  it 'reports an unknown flag instead of raising' do
    run_tape(argv_prefix: ['--sparkles']) do |status:, err:, **|
      expect(status).to eq(1)
      expect(err).to include('invalid option')
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
