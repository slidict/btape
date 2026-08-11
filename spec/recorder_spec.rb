# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Btape::Recorder do
  let(:page_class) do
    Class.new do
      attr_reader :screenshots

      def initialize
        @screenshots = []
      end

      def screenshot(path:)
        @screenshots << path
      end
    end
  end
  let(:page) { page_class.new }
  let(:directory) { '/frames' }

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
    sleep 0.05
    recorder.stop

    expect(page.screenshots.length).to be >= 3
  end

  it 're-raises an error that occurred on the background capture thread' do
    failing_page = Class.new do
      def initialize
        @calls = 0
      end

      def screenshot(*)
        @calls += 1
        raise 'boom' if @calls == 2
      end
    end.new

    recorder = described_class.new(failing_page, directory, interval: 0.01)

    recorder.start
    sleep 0.05

    expect { recorder.stop }.to raise_error('boom')
  end

  it 'does nothing when stopped without ever being started' do
    recorder = described_class.new(page, directory, interval: 60)

    expect { recorder.stop }.not_to raise_error
    expect(page.screenshots).to be_empty
  end
end
