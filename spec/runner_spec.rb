# frozen_string_literal: true

require_relative 'spec_helper'
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
  # Writes a real PNG so specs can check what survives the run, and reports
  # frames through on_frame the way Recorder does.
  let(:fake_recorder_class) do
    Class.new do
      attr_reader :paths

      def initialize(page, directory, on_frame: nil, **)
        @page = page
        @directory = directory
        @on_frame = on_frame
        @paths = []
      end

      def start
        path = File.join(@directory, format('frame-%06d.png', @paths.length))
        ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red')).save(path)
        @paths << path
        @on_frame&.call(path, @paths.length - 1)
      end

      def stop; end
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
