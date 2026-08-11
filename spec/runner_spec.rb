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
    attr_reader :visited_urls
    attr_writer :text_element

    def initialize(css_elements: {})
      @visited_urls = []
      @css_elements = css_elements
      @quit_called = false
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
  let(:fake_recorder_class) do
    Struct.new(:page, :directory) do
      def start; end

      def stop; end

      def paths
        ['frame-000000.png']
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
      browser_factory: lambda { |options|
        browser.window_size = options[:window_size]
        browser
      },
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

      output = runner.run(commands, base_directory: directory)

      expect(output).to eq(File.join(directory, 'sub/demo.gif'))
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

  it 'hands the captured frames to the gif encoder' do
    Dir.mktmpdir do |directory|
      commands = [Btape::Command.new(name: 'Output', arguments: ['demo.gif'], line_number: 1)]

      output = runner.run(commands, base_directory: directory)

      expect(gif_encoder.written).to eq([['frame-000000.png'], output])
    end
  end
end
