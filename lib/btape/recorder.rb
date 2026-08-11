# frozen_string_literal: true

require 'monitor'

module Btape
  # Captures the frames a GIF is built from.
  #
  # In :interval mode it screenshots the page on a background thread until
  # stopped. In :manual mode it captures only when the script asks with a
  # Screenshot command, which is what a tape wants when it needs one frame per
  # page rather than a few hundred near-identical ones.
  class Recorder
    def initialize(page, directory, interval: 0.1, mode: :interval, on_frame: nil, max_frames: nil,
                   lock: Monitor.new)
      @page = page
      @directory = directory
      @interval = interval
      @mode = mode.to_sym
      @on_frame = on_frame
      @max_frames = max_frames
      # Shared with the executor, so a screenshot and a command are never in
      # flight against the same page at once.
      @lock = lock
      @paths = []
      @named_paths = {}
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
      path, index = @lock.synchronize do
        exhausted! if @max_frames && @paths.length >= @max_frames

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

    # A page that hangs would otherwise be screenshotted until the disk ran
    # out, which on a shared host takes more than this run down with it.
    def exhausted!
      raise Error, "stopped after #{@max_frames} frames; raise Set MaxFrames to record for longer"
    end

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
