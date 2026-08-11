require "fileutils"
require "ferrum"
require "tmpdir"

module Btape
  class Runner
    DEFAULT_VIEWPORT = [1280, 720].freeze

    def initialize(browser_factory: ->(options) { Ferrum::Browser.new(**options) }, recorder_class: Recorder, gif_encoder: GifEncoder.new)
      @browser_factory = browser_factory
      @recorder_class = recorder_class
      @gif_encoder = gif_encoder
    end

    def run(commands, base_directory: Dir.pwd)
      output = commands.find { |command| command.name == "Output" }&.arguments&.first
      raise Error, "script must contain an Output command" unless output

      viewport = commands.find { |command| command.name == "Viewport" }&.arguments&.first
      width, height = viewport ? viewport.split("x").map(&:to_i) : DEFAULT_VIEWPORT
      output_path = File.expand_path(output, base_directory)
      FileUtils.mkdir_p(File.dirname(output_path))

      Dir.mktmpdir("btape-") do |directory|
        browser = @browser_factory.call(window_size: [width, height], browser_options: { "no-sandbox": nil })
        recorder = @recorder_class.new(browser, directory)
        begin
          recorder.start
          execute(commands, browser)
          recorder.stop
          @gif_encoder.write(recorder.paths, output_path)
        ensure
          recorder&.stop
          browser&.quit
        end
      end
      output_path
    end

    private

    def execute(commands, browser)
      commands.each do |command|
        case command.name
        when "Output", "Viewport" then next
        when "Goto" then browser.go_to(command.arguments.first)
        when "Click" then find(browser, command.arguments.first).click
        when "Type"
          element = find(browser, command.arguments.first)
          element.focus
          element.type(command.arguments.last)
        when "Sleep" then sleep_seconds(command.arguments.first)
        end
      rescue StandardError => e
        raise ScriptError.new(command.line_number, "#{command.name} failed: #{e.message}")
      end
    end

    def find(browser, selector)
      return browser.at_xpath("//*[normalize-space(text())=#{xpath_literal(selector.delete_prefix('text='))}]") || raise("element not found: #{selector}") if selector.start_with?("text=")

      browser.at_css(selector) || raise("element not found: #{selector}")
    end

    def xpath_literal(text)
      return text.inspect unless text.include?('"')
      "concat(#{text.split('"', -1).map(&:inspect).join(%q{, '"', })})"
    end

    def sleep_seconds(duration)
      value, unit = duration.match(/\A(\d+(?:\.\d+)?)(ms|s)\z/).captures
      sleep(value.to_f / (unit == "ms" ? 1000 : 1))
    end
  end
end
