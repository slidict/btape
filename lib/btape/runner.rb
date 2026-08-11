# frozen_string_literal: true

require 'fileutils'
require 'ferrum'
require 'tmpdir'

module Btape
  # Drives a headless browser through the parsed commands and captures a
  # screenshot per step, handing the frames off to GifEncoder.
  class Runner
    DEFAULT_VIEWPORT = [1280, 720].freeze

    def initialize(browser_factory: lambda { |options|
      Ferrum::Browser.new(**options)
    }, recorder_class: Recorder, gif_encoder: GifEncoder.new)
      @browser_factory = browser_factory
      @recorder_class = recorder_class
      @gif_encoder = gif_encoder
    end

    def run(commands, base_directory: Dir.pwd, settings: {})
      settings = Settings.from_commands(commands).merge(settings)
      output_path = resolve_output_path(commands, base_directory)
      geometry = resolve_viewport(commands)

      Dir.mktmpdir('btape-') { |directory| record(commands, directory, settings, geometry, output_path) }
      output_path
    end

    private

    def resolve_output_path(commands, base_directory)
      output = commands.find { |command| command.name == 'Output' }&.arguments&.first
      raise Error, 'script must contain an Output command' unless output

      path = File.expand_path(output, base_directory)
      FileUtils.mkdir_p(File.dirname(path))
      path
    end

    def resolve_viewport(commands)
      viewport = commands.find { |command| command.name == 'Viewport' }&.arguments&.first
      viewport ? viewport.split('x').map(&:to_i) : DEFAULT_VIEWPORT
    end

    def record(commands, directory, settings, geometry, output_path)
      browser = nil
      recorder = nil
      begin
        browser = open_browser(settings, geometry)
        recorder = @recorder_class.new(browser, directory)
        recorder.start
        execute(commands, browser)
        recorder.stop
        @gif_encoder.write(recorder.paths, output_path)
      ensure
        begin
          recorder&.stop
        rescue StandardError
          nil
        end
        browser&.quit
      end
    end

    def open_browser(settings, geometry)
      width, height = geometry
      browser = @browser_factory.call(browser_options(settings, geometry))
      # window_size only ever reaches Chrome as a launch flag, so a browser we
      # connected to over ws_url keeps whatever size it was started with and
      # has to be resized over the wire instead.
      browser.resize(width: width, height: height) if settings.ws_url
      browser
    end

    def browser_options(settings, geometry)
      return { ws_url: settings.ws_url } if settings.ws_url

      { window_size: geometry }
    end

    def execute(commands, browser)
      commands.each do |command|
        perform(command, browser)
      rescue StandardError => e
        raise ScriptError.new(command.line_number, "#{command.name} failed: #{e.message}")
      end
    end

    def perform(command, browser)
      case command.name
      when 'Output', 'Viewport', 'Set' then nil
      when 'Goto' then browser.go_to(command.arguments.first)
      when 'Click' then find(browser, command.arguments.first).click
      when 'Type' then type(browser, command.arguments)
      when 'Sleep' then sleep_seconds(command.arguments.first)
      end
    end

    def type(browser, arguments)
      element = find(browser, arguments.first)
      element.focus
      element.type(arguments.last)
    end

    def find(browser, selector)
      element = if selector.start_with?('text=')
                  literal = xpath_literal(selector.delete_prefix('text='))
                  browser.at_xpath("//*[normalize-space(text())=#{literal}]")
                else
                  browser.at_css(selector)
                end
      element || raise("element not found: #{selector}")
    end

    def xpath_literal(text)
      return %("#{text}") unless text.include?('"')

      parts = text.split('"', -1).map { |part| %("#{part}") }
      "concat(#{parts.join(%q(, '"', ))})"
    end

    def sleep_seconds(duration)
      value, unit = duration.match(/\A(\d+(?:\.\d+)?)(ms|s)\z/).captures
      sleep(value.to_f / (unit == 'ms' ? 1000 : 1))
    end
  end
end
