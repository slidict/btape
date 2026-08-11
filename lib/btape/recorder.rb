# frozen_string_literal: true

module Btape
  # Captures periodic screenshots of a page on a background thread until
  # stopped, building the frame sequence GifEncoder turns into a GIF.
  class Recorder
    def initialize(page, directory, interval: 0.1, on_frame: nil)
      @page = page
      @directory = directory
      @interval = interval
      @on_frame = on_frame
      @paths = []
      @mutex = Mutex.new
    end

    attr_reader :paths

    def start
      capture
      @running = true
      @thread = Thread.new do
        loop do
          sleep @interval
          capture
        end
      rescue StandardError => e
        @error = e
      end
    end

    def stop
      return unless @running

      @running = false
      @thread&.kill
      @thread&.join
      capture
      raise @error if @error
    end

    private

    def capture
      path, index = @mutex.synchronize do
        index = @paths.length
        path = File.join(@directory, format('frame-%06d.png', index))
        screenshot(path)
        @paths << path
        [path, index]
      end
      # Outside the lock: the callback is the caller's code and may take as
      # long as it likes without holding up the next capture.
      @on_frame&.call(path, index)
    end

    def screenshot(path)
      @page.screenshot(path: path)
    end
  end
end
