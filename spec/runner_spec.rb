# frozen_string_literal: true

require_relative 'spec_helper'
require 'stringio'
require 'tmpdir'

# Fakes standing in for Ferrum, exercising Runner's command dispatch and
# error handling without needing a real browser.
module FakeBrowser
  class Element
    attr_reader :clicked, :focused, :typed

    def click
      @clicked = true
    end

    def focus
      @focused = true
    end

    def type(text)
      @typed = text
    end
  end

  class Browser
    attr_accessor :window_size
    attr_reader :visited_urls, :resized_to, :connected_with
    attr_writer :text_element

    def initialize(css_elements: {})
      @visited_urls = []
      @css_elements = css_elements
      @quit_called = false
    end

    def connect(options)
      @connected_with = options
      @window_size = options[:window_size]
      self
    end

    def resize(width:, height:)
      @resized_to = [width, height]
    end

    def quit_called?
      @quit_called
    end

    def go_to(url)
      @visited_urls << url
    end

    def at_css(selector)
      @css_elements[selector]
    end

    def at_xpath(_expression)
      @text_element
    end

    def quit
      @quit_called = true
    end
  end
end

RSpec.describe Btape::Runner do
  let(:browser) { FakeBrowser::Browser.new(css_elements: { '#email' => email_field }) }
  let(:email_field) { FakeBrowser::Element.new }
  let(:login_button) { FakeBrowser::Element.new }
  # Writes a real PNG so specs can check what survives the run, and mirrors
  # Recorder's interval/manual split and on_frame callback.
  let(:fake_recorder_class) do
    Class.new do
      attr_reader :paths, :named_paths, :interval, :mode, :max_frames, :lock

      def initialize(page, directory, interval: 0.1, mode: :interval, on_frame: nil, max_frames: nil, lock: nil)
        @page = page
        @directory = directory
        @interval = interval
        @mode = mode
        @on_frame = on_frame
        @max_frames = max_frames
        @lock = lock
        @paths = []
        @named_paths = {}
      end

      def start
        capture unless @mode.to_sym == :manual
      end

      def stop; end

      def capture(name: nil)
        path = File.join(@directory, name ? "frame-#{name}.png" : format('frame-%06d.png', @paths.length))
        ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red')).save(path)
        index = @paths.length
        @paths << path
        @named_paths[name] = path if name
        @on_frame&.call(path, index)
        path
      end
    end
  end
  let(:fake_gif_encoder_class) do
    Struct.new(:written) do
      def write(paths, output)
        self.written = [paths, output]
      end
    end
  end
  let(:gif_encoder) { fake_gif_encoder_class.new }

  def runner
    described_class.new(
      browser_factory: ->(options) { browser.connect(options) },
      recorder_class: fake_recorder_class,
      gif_encoder: gif_encoder
    )
  end

  it 'raises when the script has no Output command' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Goto', arguments: ['http://example.test'], line_number: 1)]

      expect { runner.run(commands, base_directory: directory) }
        .to raise_error(Btape::Error, 'script must contain an Output command')
    end
  end

  it 'resolves the output path relative to the base directory' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Output', arguments: ['sub/demo.gif'], line_number: 1)]

      result = runner.run(commands, base_directory: directory)

      expect(result.output_path).to eq(File.join(directory, 'sub/demo.gif'))
    end
  end

  it 'defaults to a 1280x720 viewport' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]

      runner.run(commands, base_directory: directory)

      expect(browser.window_size).to eq([1280, 720])
    end
  end

  it 'honours an explicit Viewport command' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Viewport', arguments: ['800x600'], line_number: 2)
      ]

      runner.run(commands, base_directory: directory)

      expect(browser.window_size).to eq([800, 600])
    end
  end

  it 'drives Goto, Click, Type and Sleep against the browser' do
    browser.text_element = login_button
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Goto', arguments: ['http://example.test'], line_number: 2),
        Btape::Command.new(name: 'Click', arguments: ['text=Login'], line_number: 3),
        Btape::Command.new(name: 'Type', arguments: ['#email', 'demo@example.com'], line_number: 4),
        Btape::Command.new(name: 'Sleep', arguments: ['1ms'], line_number: 5)
      ]

      runner.run(commands, base_directory: directory)

      expect(browser.visited_urls).to eq(['http://example.test'])
      expect(login_button.clicked).to be true
      expect(email_field.focused).to be true
      expect(email_field.typed).to eq('demo@example.com')
    end
  end

  it 'wraps a failing command in a ScriptError that includes the line number' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Click', arguments: ['#missing'], line_number: 3)
      ]

      expect { runner.run(commands, base_directory: directory) }
        .to raise_error(Btape::ScriptError, 'line 3: Click failed: element not found: #missing')
    end
  end

  it 'quits the browser even when a command fails' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Click', arguments: ['#missing'], line_number: 2)
      ]

      expect { runner.run(commands, base_directory: directory) }.to raise_error(Btape::ScriptError)
      expect(browser.quit_called?).to be true
    end
  end

  it 'connects to a remote browser when the tape sets WsUrl' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Set', arguments: %w[WsUrl ws://chrome:3000], line_number: 2)
      ]

      runner.run(commands, base_directory: directory)

      expect(browser.connected_with).to eq({ ws_url: 'ws://chrome:3000' })
    end
  end

  # window_size is only a Chrome launch flag, so a browser reached over
  # ws_url has to be resized over the wire instead.
  it 'resizes a remote browser to the viewport' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Viewport', arguments: ['800x600'], line_number: 2),
        Btape::Command.new(name: 'Set', arguments: %w[WsUrl ws://chrome:3000], line_number: 3)
      ]

      runner.run(commands, base_directory: directory)

      expect(browser.resized_to).to eq([800, 600])
    end
  end

  it 'does not resize a browser it launched itself' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]

      runner.run(commands, base_directory: directory)

      expect(browser.resized_to).to be_nil
    end
  end

  it 'lets the caller override what the tape set' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Set', arguments: %w[WsUrl ws://from-tape:3000], line_number: 2)
      ]

      runner.run(commands, base_directory: directory, settings: { ws_url: 'ws://from-caller:3000' })

      expect(browser.connected_with).to eq({ ws_url: 'ws://from-caller:3000' })
    end
  end

  it 'hands the captured frames to the gif encoder' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]

      result = runner.run(commands, base_directory: directory)
      paths, output = gif_encoder.written

      expect(paths.length).to eq(1)
      expect(output).to eq(result.output_path)
    end
  end

  it 'reports the frame count and viewport in the result' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Viewport', arguments: ['800x600'], line_number: 2)
      ]

      result = runner.run(commands, base_directory: directory)

      expect(result.frame_count).to eq(1)
      expect([result.width, result.height]).to eq([800, 600])
    end
  end

  # Without somewhere to keep them the frames live in a temporary directory
  # that is gone by the time run returns, so reporting their paths would be
  # handing back paths to files that no longer exist.
  it 'leaves frame_paths empty when the frames were not kept' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]

      result = runner.run(commands, base_directory: directory)

      expect(result.frame_paths).to be_empty
    end
  end

  it 'keeps the frames on disk when given a frames directory' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]

      result = runner.run(commands, base_directory: directory, frames_directory: 'frames')

      expect(result.frame_paths).to eq([File.join(directory, 'frames', 'frame-000000.png')])
      expect(result.frame_paths).to all(satisfy { |path| File.exist?(path) })
    end
  end

  it 'builds the recorder from the capture settings' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Set', arguments: %w[CaptureMode manual], line_number: 2),
        Btape::Command.new(name: 'Set', arguments: %w[Framerate 20], line_number: 3),
        Btape::Command.new(name: 'Screenshot', arguments: [], line_number: 4)
      ]
      recorders = []
      recorder_class = fake_recorder_class
      spy = Class.new(recorder_class) do
        define_method(:initialize) do |*args, **options|
          super(*args, **options)
          recorders << self
        end
      end

      described_class.new(
        browser_factory: ->(options) { browser.connect(options) },
        recorder_class: spy,
        gif_encoder: gif_encoder
      ).run(commands, base_directory: directory)

      expect(recorders.first.mode).to eq('manual')
      expect(recorders.first.interval).to eq(0.05)
    end
  end

  it 'records a Screenshot NAME under that name' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Set', arguments: %w[CaptureMode manual], line_number: 2),
        Btape::Command.new(name: 'Screenshot', arguments: ['cover'], line_number: 3)
      ]

      result = runner.run(commands, base_directory: directory, frames_directory: 'frames')

      expect(result.named_frames).to eq('cover' => File.join(directory, 'frames', 'frame-cover.png'))
      expect(result.frame_count).to eq(1)
    end
  end

  describe 'output:' do
    let(:gif_encoder) { Btape::GifEncoder.new }

    it 'writes the gif into an IO and reports no path' do
      Dir.mktmpdir do |directory|
        commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]
        buffer = StringIO.new(+''.b)

        result = runner.run(commands, base_directory: directory, output: buffer)

        expect(buffer.string).to start_with('GIF89a')
        expect(result.output_path).to be_nil
        expect(File.exist?(File.join(directory, 'demo.gif'))).to be false
      end
    end

    it 'writes to a path the caller gives instead of the tape' do
      Dir.mktmpdir do |directory|
        commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]

        result = runner.run(commands, base_directory: directory, output: 'elsewhere/other.gif')

        expect(result.output_path).to eq(File.join(directory, 'elsewhere/other.gif'))
        expect(File.exist?(result.output_path)).to be true
      end
    end
  end

  describe 'unwinding' do
    let(:logger) { instance_double(Btape::NullLogger, debug: nil, info: nil, warn: nil) }

    def failing_recorder_class(error)
      Class.new(fake_recorder_class) do
        define_method(:stop) { raise error }
      end
    end

    # The exception on its way out is the one that says why the run failed;
    # a failure to stop the recorder must not replace it.
    it 'keeps the original failure when the recorder cannot be stopped' do
      Dir.mktmpdir do |directory|
        commands = [
          Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
          Btape::Command.new(name: 'Click', arguments: ['#missing'], line_number: 2)
        ]
        runner = described_class.new(
          browser_factory: ->(options) { browser.connect(options) },
          recorder_class: failing_recorder_class(RuntimeError.new('recorder is wedged')),
          gif_encoder: gif_encoder,
          logger: logger
        )

        expect { runner.run(commands, base_directory: directory) }
          .to raise_error(Btape::ScriptError, /element not found: #missing/)
      end
    end

    it 'reports the failure to stop rather than discarding it' do
      Dir.mktmpdir do |directory|
        commands = [
          Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
          Btape::Command.new(name: 'Click', arguments: ['#missing'], line_number: 2)
        ]
        runner = described_class.new(
          browser_factory: ->(options) { browser.connect(options) },
          recorder_class: failing_recorder_class(RuntimeError.new('recorder is wedged')),
          gif_encoder: gif_encoder,
          logger: logger
        )

        expect { runner.run(commands, base_directory: directory) }.to raise_error(Btape::ScriptError)
        expect(logger).to have_received(:warn).with(/could not stop the recorder: recorder is wedged/)
      end
    end

    it 'still quits the browser when the recorder cannot be stopped' do
      Dir.mktmpdir do |directory|
        commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]
        runner = described_class.new(
          browser_factory: ->(options) { browser.connect(options) },
          recorder_class: failing_recorder_class(RuntimeError.new('recorder is wedged')),
          gif_encoder: gif_encoder,
          logger: logger
        )

        expect { runner.run(commands, base_directory: directory) }.to raise_error('recorder is wedged')
        expect(browser.quit_called?).to be true
      end
    end
  end

  it 'gives up on a run that outlasts Set Timeout' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Set', arguments: %w[Timeout 10ms], line_number: 2),
        Btape::Command.new(name: 'Sleep', arguments: ['5s'], line_number: 3)
      ]

      expect { runner.run(commands, base_directory: directory) }
        .to raise_error(Btape::TimeoutError, /run timed out after 0.01s/)
      expect(browser.quit_called?).to be true
    end
  end

  it 'passes the frame limit to the recorder' do
    Dir.mktmpdir do |directory|
      commands = [
        Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1),
        Btape::Command.new(name: 'Set', arguments: %w[MaxFrames 5], line_number: 2)
      ]
      recorders = []
      spy = Class.new(fake_recorder_class) do
        define_method(:initialize) do |*args, **options|
          super(*args, **options)
          recorders << self
        end
      end

      described_class.new(
        browser_factory: ->(options) { browser.connect(options) },
        recorder_class: spy,
        gif_encoder: gif_encoder
      ).run(commands, base_directory: directory)

      expect(recorders.first.max_frames).to eq(5)
    end
  end

  it 'hands each frame to on_frame as it is captured' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]
      seen = []

      runner.run(commands, base_directory: directory, on_frame: ->(path, index) { seen << [path, index] })

      expect(seen.length).to eq(1)
      expect(seen.first.last).to eq(0)
    end
  end
end
