# frozen_string_literal: true

require_relative 'spec_helper'
require 'timeout'

RSpec.describe Btape::Recorder do
  let(:page_class) do
    Class.new do
      attr_reader :screenshots, :captures

      def initialize
        @screenshots = []
        @captures = Queue.new
      end

      def screenshot(path:)
        @screenshots << path
        @captures << path
      end
    end
  end
  let(:page) { page_class.new }
  let(:directory) { '/frames' }

  # Blocks until `count` captures have been observed on the background
  # thread, instead of guessing how long that takes with a fixed sleep.
  def wait_for_captures(queue, count)
    Timeout.timeout(1) { count.times { queue.pop } }
  end

  it 'captures a frame immediately on start and again on stop' do
    recorder = described_class.new(page, directory, interval: 60)

    recorder.start
    recorder.stop

    expect(page.screenshots.length).to eq(2)
  end

  it 'names frames sequentially inside the given directory' do
    recorder = described_class.new(page, directory, interval: 60)

    recorder.start
    recorder.stop

    expect(recorder.paths).to eq(
      [File.join(directory, 'frame-000000.png'), File.join(directory, 'frame-000001.png')]
    )
  end

  it 'keeps capturing on a background thread until stopped' do
    recorder = described_class.new(page, directory, interval: 0.01)

    recorder.start
    # The initial synchronous capture from #start is one of these; waiting
    # for a few more proves the background thread is also capturing.
    wait_for_captures(page.captures, 4)
    recorder.stop

    expect(page.screenshots.length).to be >= 4
  end

  it 're-raises an error that occurred on the background capture thread' do
    failing_page = Class.new do
      attr_reader :captures

      def initialize
        @calls = 0
        @captures = Queue.new
      end

      def screenshot(*)
        @calls += 1
        raise 'boom' if @calls == 2
      ensure
        @captures << @calls
      end
    end.new

    recorder = described_class.new(failing_page, directory, interval: 0.01)

    recorder.start
    # Wait until the second capture (the one that raises) has actually run,
    # rather than guessing at a sleep long enough for it to have happened.
    wait_for_captures(failing_page.captures, 2)

    expect { recorder.stop }.to raise_error('boom')
  end

  it 'does nothing when stopped without ever being started' do
    recorder = described_class.new(page, directory, interval: 60)

    expect { recorder.stop }.not_to raise_error
    expect(page.screenshots).to be_empty
  end
end
