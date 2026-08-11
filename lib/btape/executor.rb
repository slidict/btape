# frozen_string_literal: true

require_relative 'duration'

module Btape
  # Performs the parsed commands against a browser, turning any failure into a
  # ScriptError that points back at the line it came from.
  #
  # It lives apart from Runner because Runner's job is the recording session
  # around the script — the browser, the frames, the GIF — while this is the
  # script itself, and only this grows with each new command.
  class Executor
    def initialize(browser:, recorder:, settings:)
      @browser = browser
      @recorder = recorder
      @settings = settings
    end

    def call(commands)
      commands.each do |command|
        perform(command)
      rescue StandardError => e
        raise ScriptError.new(command.line_number, "#{command.name} failed: #{e.message}")
      end
    end

    private

    def perform(command)
      case command.name
      when 'Output', 'Viewport', 'Set' then nil
      when 'Goto' then @browser.go_to(command.arguments.first)
      when 'Click' then find(command.arguments.first).click
      when 'Type' then type(command.arguments)
      when 'Sleep' then sleep(Duration.parse(command.arguments.first))
      when 'Screenshot' then @recorder.capture(name: command.arguments.first)
      end
    end

    def type(arguments)
      element = find(arguments.first)
      element.focus
      element.type(arguments.last)
    end

    def find(selector)
      element = if selector.start_with?('text=')
                  literal = xpath_literal(selector.delete_prefix('text='))
                  @browser.at_xpath("//*[normalize-space(text())=#{literal}]")
                else
                  @browser.at_css(selector)
                end
      element || raise("element not found: #{selector}")
    end

    def xpath_literal(text)
      return %("#{text}") unless text.include?('"')

      parts = text.split('"', -1).map { |part| %("#{part}") }
      "concat(#{parts.join(%q(, '"', ))})"
    end
  end
end
