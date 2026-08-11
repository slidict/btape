# frozen_string_literal: true

require 'monitor'
require_relative 'duration'
require_relative 'null_logger'

module Btape
  # Performs the parsed commands against a browser, turning any failure into a
  # ScriptError that points back at the line it came from.
  #
  # It lives apart from Runner because Runner's job is the recording session
  # around the script — the browser, the frames, the GIF — while this is the
  # script itself, and only this grows with each new command.
  class Executor
    # Commands that do something at run time, and the method that does it.
    # Output, Viewport and Set are read before the run starts and have no
    # behaviour of their own here.
    HANDLERS = {
      'Goto' => :goto, 'Click' => :click, 'Type' => :enter, 'Sleep' => :pause,
      'Screenshot' => :screenshot, 'Evaluate' => :evaluate,
      'WaitFor' => :wait_for_element, 'WaitForJS' => :wait_for_js,
      'Frame' => :frame, 'Press' => :press
    }.freeze

    MAIN_FRAME = 'main'

    def initialize(browser:, recorder:, settings:, lock: Monitor.new, logger: NullLogger.new)
      @browser = browser
      # Elements and JavaScript are looked up in the current frame, which
      # starts as the page itself and moves when a Frame command says so.
      @target = browser
      @recorder = recorder
      @settings = settings
      @lock = lock
      @logger = logger
    end

    def call(commands)
      commands.each do |command|
        @logger.debug("btape: line #{command.line_number}: #{command.name}")
        perform(command)
      rescue StandardError => e
        raise ScriptError.new(command.line_number, "#{command.name} failed: #{e.message}")
      end
    end

    private

    # Held across each exchange with the browser, and shared with the
    # recorder, so a screenshot taken on the recorder's thread is never in
    # flight at the same time as a command on this one.
    #
    # It is deliberately not held for a whole command: Sleep and the waiting
    # commands spend most of their time not talking to the browser at all,
    # and holding the lock through that would leave interval recording with
    # nothing to capture for the duration.
    def locked(&)
      @lock.synchronize(&)
    end

    def perform(command)
      handler = HANDLERS[command.name]
      send(handler, *command.arguments) if handler
    end

    def goto(url)
      locked { @browser.go_to(url) }
      # Whatever frame we were in belongs to the page we just left.
      @target = @browser
    end

    # Points the following commands at an iframe, so a tape can reach an API
    # inside it — a slide deck's own navigation, say — rather than only what
    # the outer document exposes. Nesting works by switching again from
    # within, and `Frame main` returns to the page.
    def frame(selector)
      return @target = @browser if selector == MAIN_FRAME

      @target = find(selector).frame || raise("#{selector} is not a frame")
    end

    def press(key, count = '1')
      Integer(count, 10).times { locked { @browser.keyboard.type(key.to_sym) } }
    end

    def click(selector)
      locked { find(selector).click }
    end

    def enter(selector, text)
      locked do
        element = find(selector)
        element.focus
        element.type(text)
      end
    end

    def pause(duration)
      sleep(Duration.parse(duration))
    end

    def screenshot(name = nil)
      @recorder.capture(name: name)
    end

    def evaluate(expression)
      locked { @target.evaluate(expression) }
    end

    def wait_for_element(selector, timeout = nil)
      wait_until(timeout, "#{selector} to appear") { element(selector) }
    end

    def wait_for_js(expression, timeout = nil)
      wait_until(timeout, "#{expression} to be true") { evaluate(expression) }
    end

    # Polls until the block has been satisfied WaitStable times in a row. The
    # streak matters for pages that report readiness before they have settled:
    # a single true reading can land mid-render, several in a row cannot.
    #
    # A block that raises counts as not-yet-satisfied, since a page part-way
    # through loading will happily throw on a property that is about to
    # exist. The last error is reported if the wait times out, so a broken
    # expression still surfaces rather than being silently polled forever.
    def wait_until(timeout, description)
      timeout = timeout ? Duration.parse(timeout) : @settings.wait_timeout
      deadline = monotonic + timeout
      stable = 0
      failure = nil

      loop do
        satisfied = begin
          yield
        rescue StandardError => e
          failure = e
          false
        end

        stable = satisfied ? stable + 1 : 0
        return if stable >= @settings.wait_stable
        raise Error, timed_out(description, timeout, failure) if monotonic >= deadline

        sleep(@settings.wait_interval)
      end
    end

    def timed_out(description, timeout, failure)
      message = "timed out after #{timeout}s waiting for #{description}"
      failure ? "#{message} (last error: #{failure.message})" : message
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def find(selector)
      element(selector) || raise("element not found: #{selector}")
    end

    def element(selector)
      locked do
        next @target.at_css(selector) unless selector.start_with?('text=')

        literal = xpath_literal(selector.delete_prefix('text='))
        @target.at_xpath("//*[normalize-space(text())=#{literal}]")
      end
    end

    def xpath_literal(text)
      return %("#{text}") unless text.include?('"')

      parts = text.split('"', -1).map { |part| %("#{part}") }
      "concat(#{parts.join(%q(, '"', ))})"
    end
  end
end
