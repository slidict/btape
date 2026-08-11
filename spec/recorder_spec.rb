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

  it 'hands each captured frame to on_frame with its index' do
    seen = []
    recorder = described_class.new(page, directory, interval: 60, on_frame: ->(path, index) { seen << [path, index] })

    recorder.start
    recorder.stop

    expect(seen).to eq(
      [[File.join(directory, 'frame-000000.png'), 0], [File.join(directory, 'frame-000001.png'), 1]]
    )
  end

  it 'does nothing when stopped without ever being started' do
    recorder = described_class.new(page, directory, interval: 60)

    expect { recorder.stop }.not_to raise_error
    expect(page.screenshots).to be_empty
  end

  describe 'manual mode' do
    # The point of manual mode is that nothing is captured behind the
    # script's back, so a 20-page deck yields 20 frames and not 600.
    it 'captures nothing on start or stop' do
      recorder = described_class.new(page, directory, interval: 0.01, mode: :manual)

      recorder.start
      recorder.stop

      expect(page.screenshots).to be_empty
    end

    it 'captures only when the script asks' do
      recorder = described_class.new(page, directory, interval: 0.01, mode: :manual)

      recorder.start
      recorder.capture
      recorder.capture
      recorder.stop

      expect(recorder.paths.length).to eq(2)
    end
  end

  # A page that hangs would otherwise be screenshotted until the disk ran out.
  it 'stops once it has captured MaxFrames' do
    recorder = described_class.new(page, directory, mode: :manual, max_frames: 2)

    recorder.capture
    recorder.capture

    expect { recorder.capture }.to raise_error(Btape::Error, /stopped after 2 frames/)
  end

  it 'reports the frame limit reached on the background thread when stopped' do
    recorder = described_class.new(page, directory, interval: 0.001, max_frames: 3)

    recorder.start
    wait_for_captures(page.captures, 3)

    expect { recorder.stop }.to raise_error(Btape::Error, /stopped after 3 frames/)
  end

  it 'stops only once, so unwinding twice is harmless' do
    recorder = described_class.new(page, directory, interval: 60)

    recorder.start
    recorder.stop
    recorder.stop

    expect(page.screenshots.length).to eq(2)
  end

  it 'takes the lock it shares with the executor while capturing' do
    lock = Monitor.new
    held = nil
    page.define_singleton_method(:screenshot) { |**| held = lock.mon_owned? }
    recorder = described_class.new(page, directory, mode: :manual, lock: lock)

    recorder.capture

    expect(held).to be true
  end

  it 'gives a named frame a predictable path and records it by name' do
    recorder = described_class.new(page, directory, mode: :manual)

    path = recorder.capture(name: 'page-01')

    expect(path).to eq(File.join(directory, 'frame-page-01.png'))
    expect(recorder.named_paths).to eq('page-01' => path)
  end

  it 'keeps numbering unnamed frames sequentially around named ones' do
    recorder = described_class.new(page, directory, mode: :manual)

    recorder.capture
    recorder.capture(name: 'cover')
    recorder.capture

    expect(recorder.paths.last).to eq(File.join(directory, 'frame-000002.png'))
  end
end
