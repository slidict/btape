require "coelacanth"

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

    # Coelacanth versions expose either a module capture API or a capturer
    # object. Supporting both keeps btape usable while its young API settles.
    def screenshot(path)
      if Coelacanth.respond_to?(:capture)
        Coelacanth.capture(@page, path)
      elsif defined?(Coelacanth::Screenshot)
        Coelacanth::Screenshot.new(@page).capture(path)
      else
        raise Error, "this coelacanth version has no supported screenshot API"
      end
    end
  end
end
