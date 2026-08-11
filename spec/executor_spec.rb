# frozen_string_literal: true

require_relative 'spec_helper'

# Enough of Ferrum for Executor's dispatch: a page that answers lookups and
# evaluate, the frame an iframe node hands back, and the keyboard.
module FakeFerrum
  class Keyboard
    attr_reader :typed

    def initialize
      @typed = []
    end

    def type(key)
      @typed << key
    end
  end

  # A Frame answers the same lookup and evaluate calls a page does.
  class Frame
    attr_reader :evaluated

    def initialize
      @evaluated = []
    end

    def evaluate(expression)
      @evaluated << expression
      nil
    end

    def at_css(_selector)
      nil
    end
  end

  Node = Struct.new(:frame)

  # Answers each evaluate with the next queued value, raising anything queued
  # as an exception, so a spec can describe a page that becomes ready part way
  # through a wait. An element queued as an array is answered one entry per
  # lookup, for the same reason.
  class Browser
    attr_reader :evaluated, :visited_urls, :keyboard

    def initialize(answers: [], elements: {})
      @answers = answers
      @elements = elements
      @evaluated = []
      @visited_urls = []
      @keyboard = Keyboard.new
    end

    def evaluate(expression)
      @evaluated << expression
      answer = @answers.empty? ? nil : @answers.shift
      raise answer if answer.is_a?(Exception)

      answer
    end

    def at_css(selector)
      found = @elements[selector]
      found.is_a?(Array) ? found.shift : found
    end

    def at_xpath(_expression)
      nil
    end

    def go_to(url)
      @visited_urls << url
    end
  end
end

RSpec.describe Btape::Executor do
  let(:browser_class) { FakeFerrum::Browser }
  let(:recorder) { instance_double(Btape::Recorder) }

  def executor(browser, settings = {})
    described_class.new(
      browser: browser,
      recorder: recorder,
      settings: Btape::Settings.new({ wait_interval: 0.001 }.merge(settings))
    )
  end

  def command(name, *arguments, line_number: 1)
    Btape::Command.new(name: name, arguments: arguments, line_number: line_number)
  end

  it 'evaluates javascript against the browser' do
    browser = browser_class.new

    executor(browser).call([command('Evaluate', 'Reveal.slide(3, 0)')])

    expect(browser.evaluated).to eq(['Reveal.slide(3, 0)'])
  end

  it 'waits until a javascript expression is true' do
    browser = browser_class.new(answers: [false, false, true])

    executor(browser).call([command('WaitForJS', 'window.READY')])

    expect(browser.evaluated.length).to eq(3)
  end

  # A page that flips its readiness flag before it has settled would be
  # screenshotted mid-render, so WaitStable asks for a streak.
  it 'requires the expression to hold for WaitStable checks in a row' do
    browser = browser_class.new(answers: [true, true, false, true, true, true])

    executor(browser, wait_stable: 3).call([command('WaitForJS', 'window.READY')])

    expect(browser.evaluated.length).to eq(6)
  end

  it 'gives up after the timeout and names what it was waiting for' do
    browser = browser_class.new(answers: [false] * 100)

    expect { executor(browser).call([command('WaitForJS', 'window.READY', '10ms')]) }
      .to raise_error(Btape::ScriptError, /timed out after 0.01s waiting for window.READY to be true/)
  end

  it 'prefers the timeout on the command over the setting' do
    browser = browser_class.new(answers: [false] * 100)

    expect { executor(browser, wait_timeout: 30.0).call([command('WaitForJS', 'x', '10ms')]) }
      .to raise_error(Btape::ScriptError, /timed out after 0.01s/)
  end

  # A page part way through loading throws on properties that are about to
  # exist, so an error means not-yet rather than failure — but a genuinely
  # broken expression still has to surface, not be polled forever in silence.
  it 'treats a raising expression as not ready yet' do
    browser = browser_class.new(answers: [RuntimeError.new('undefined is not an object'), true])

    expect { executor(browser).call([command('WaitForJS', 'window.READY')]) }.not_to raise_error
  end

  it 'reports the last error when a raising expression never comes good' do
    browser = browser_class.new(answers: Array.new(100) { RuntimeError.new('READY is not defined') })

    expect { executor(browser).call([command('WaitForJS', 'window.READY', '10ms')]) }
      .to raise_error(Btape::ScriptError, /last error: READY is not defined/)
  end

  it 'waits for an element to appear' do
    browser = browser_class.new(elements: { '#deck' => [nil, nil, :element] })

    expect { executor(browser).call([command('WaitFor', '#deck')]) }.not_to raise_error
  end

  it 'gives up when the element never appears' do
    browser = browser_class.new(elements: { '#deck' => nil })

    expect { executor(browser).call([command('WaitFor', '#deck', '10ms')]) }
      .to raise_error(Btape::ScriptError, /timed out after 0.01s waiting for #deck to appear/)
  end

  describe 'Frame' do
    it 'sends later commands into the iframe' do
      frame = FakeFerrum::Frame.new
      browser = browser_class.new(elements: { '#preview' => FakeFerrum::Node.new(frame) })

      executor(browser).call(
        [command('Frame', '#preview'), command('Evaluate', 'Reveal.slide(2, 0)')]
      )

      expect(frame.evaluated).to eq(['Reveal.slide(2, 0)'])
      expect(browser.evaluated).to be_empty
    end

    it 'returns to the page on Frame main' do
      frame = FakeFerrum::Frame.new
      browser = browser_class.new(elements: { '#preview' => FakeFerrum::Node.new(frame) })

      executor(browser).call(
        [command('Frame', '#preview'), command('Frame', 'main'), command('Evaluate', 'document.title')]
      )

      expect(browser.evaluated).to eq(['document.title'])
    end

    # The frame we were in belonged to the page we just left.
    it 'returns to the page after navigating' do
      frame = FakeFerrum::Frame.new
      browser = browser_class.new(elements: { '#preview' => FakeFerrum::Node.new(frame) })

      executor(browser).call(
        [command('Frame', '#preview'), command('Goto', 'http://example.test'), command('Evaluate', 'x')]
      )

      expect(browser.evaluated).to eq(['x'])
    end

    it 'reports a selector that is not a frame' do
      browser = browser_class.new(elements: { '#heading' => FakeFerrum::Node.new(nil) })

      expect { executor(browser).call([command('Frame', '#heading')]) }
        .to raise_error(Btape::ScriptError, /#heading is not a frame/)
    end
  end

  describe 'Press' do
    it 'types the key once by default' do
      browser = browser_class.new

      executor(browser).call([command('Press', 'Right')])

      expect(browser.keyboard.typed).to eq([:Right])
    end

    it 'repeats the key COUNT times' do
      browser = browser_class.new

      executor(browser).call([command('Press', 'Right', '3')])

      expect(browser.keyboard.typed).to eq(%i[Right Right Right])
    end
  end

  it 'reports the line a failing command came from' do
    browser = browser_class.new(elements: { '#deck' => nil })

    expect { executor(browser).call([command('WaitFor', '#deck', '10ms', line_number: 7)]) }
      .to raise_error(Btape::ScriptError) { |error| expect(error.line_number).to eq(7) }
  end
end
