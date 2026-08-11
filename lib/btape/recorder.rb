module Btape
  class Recorder
    def initialize(page, directory, interval: 0.1)
      @page = page
      @directory = directory
      @interval = interval
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
      @mutex.synchronize do
        path = File.join(@directory, format("frame-%06d.png", @paths.length))
        screenshot(path)
        @paths << path
      end
    end

    def screenshot(path)
      @page.screenshot(path: path)
    end
  end
end
