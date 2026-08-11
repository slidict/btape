# frozen_string_literal: true

module Btape
  # Captures the frames a GIF is built from.
  #
  # In :interval mode it screenshots the page on a background thread until
  # stopped. In :manual mode it captures only when the script asks with a
  # Screenshot command, which is what a tape wants when it needs one frame per
  # page rather than a few hundred near-identical ones.
  class Recorder
    def initialize(page, directory, interval: 0.1, mode: :interval, on_frame: nil)
      @page = page
      @directory = directory
      @interval = interval
      @mode = mode.to_sym
      @on_frame = on_frame
      @paths = []
      @named_paths = {}
      @mutex = Mutex.new
    end

    attr_reader :paths, :named_paths

    def start
      return if manual?

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

    # Captures one frame now. A name puts it at a predictable path, so a
    # caller can pick a particular frame out of the run.
    def capture(name: nil)
      path, index = @mutex.synchronize do
        path = File.join(@directory, filename(name))
        screenshot(path)
        index = @paths.length
        @paths << path
        @named_paths[name] = path if name
        [path, index]
      end
      # Outside the lock: the callback is the caller's code and may take as
      # long as it likes without holding up the next capture.
      @on_frame&.call(path, index)
      path
    end

    private

    def manual?
      @mode == :manual
    end

    def filename(name)
      name ? "frame-#{name}.png" : format('frame-%06d.png', @paths.length)
    end

    def screenshot(path)
      @page.screenshot(path: path)
    end
  end
end
