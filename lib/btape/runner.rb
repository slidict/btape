# frozen_string_literal: true

require 'fileutils'
require 'ferrum'
require 'monitor'
require 'timeout'
require 'tmpdir'

module Btape
  # The recording session around a script: opens the browser, starts the
  # recorder, hands the commands to Executor, and turns the captured frames
  # into a GIF.
  class Runner
    DEFAULT_VIEWPORT = [1280, 720].freeze

    # How long unwinding gets. Set Timeout bounds the run, but the thing that
    # usually trips it is a wedged browser, and both stopping the recorder and
    # quitting the browser then talk to it — so without a deadline of their
    # own they would hang the process after the timeout had already fired.
    CLEANUP_TIMEOUT = 10

    # Everything one run threads through recording, kept in one object rather
    # than a parameter list that grows with each new command.
    Context = Struct.new(:commands, :directory, :settings, :geometry, :sink, :output_path, :on_frame, :keep_frames,
                         keyword_init: true)

    # An encoder passed here is used as given; otherwise one is built from the
    # settings the tape and the caller supplied.
    def initialize(browser_factory: lambda { |options|
      Ferrum::Browser.new(**options)
    }, recorder_class: Recorder, gif_encoder: nil, logger: NullLogger.new)
      @browser_factory = browser_factory
      @recorder_class = recorder_class
      @gif_encoder = gif_encoder
      @logger = logger
    end

    # Returns a Result. Pass `frames_directory:` to keep the PNG frames after
    # the run, `on_frame:` to be handed each one as it is captured, and
    # `output:` to override the tape's Output with another path or with an IO
    # to write the GIF into.
    def run(commands, base_directory: Dir.pwd, settings: {}, frames_directory: nil, on_frame: nil, output: nil)
      settings = Settings.from_commands(commands).merge(settings)
      sink, output_path = resolve_output(commands, base_directory, output)
      context = Context.new(
        commands: commands,
        settings: settings,
        geometry: resolve_viewport(commands),
        sink: sink,
        output_path: output_path,
        on_frame: on_frame,
        keep_frames: !frames_directory.nil?
      )

      within_frames_directory(frames_directory, base_directory) do |directory|
        context.directory = directory
        record(context)
      end
    end

    private

    # Frames go to a temporary directory that is cleaned up as the run
    # unwinds, unless the caller named a directory to keep them in.
    def within_frames_directory(frames_directory, base_directory, &block)
      return Dir.mktmpdir('btape-', &block) unless frames_directory

      directory = File.expand_path(frames_directory, base_directory)
      FileUtils.mkdir_p(directory)
      block.call(directory)
    end

    # Returns where the GIF goes and, when that is a file, its path. Writing
    # into an IO leaves no path behind, so Result reports nil rather than a
    # path nothing was written to.
    def resolve_output(commands, base_directory, override)
      declared = commands.find { |command| command.name == 'Output' }&.arguments&.first
      raise Error, 'script must contain an Output command' unless declared
      return [override, nil] if override.respond_to?(:write)

      path = File.expand_path(override || declared, base_directory)
      FileUtils.mkdir_p(File.dirname(path))
      [path, path]
    end

    def resolve_viewport(commands)
      viewport = commands.find { |command| command.name == 'Viewport' }&.arguments&.first
      viewport ? viewport.split('x').map(&:to_i) : DEFAULT_VIEWPORT
    end

    def record(context)
      browser = nil
      recorder = nil
      lock = Monitor.new
      begin
        timed(context.settings.timeout) do
          browser = open_browser(context.settings, context.geometry)
          recorder = build_recorder(browser, context, lock)
          recorder.start
          execute(context, browser, recorder, lock)
          recorder.stop
        end
        # Outside the deadline: it is there to bound the browser session, and
        # interrupting a write part-way through would leave a truncated GIF at
        # the output path that nothing downstream could tell from a whole one.
        encoder(context.settings).write(recorder.paths, context.sink)
        result(context, recorder)
      ensure
        cleanup(recorder, browser)
      end
    end

    # A page that never finishes loading would otherwise record until the
    # frame limit or the disk stopped it.
    def timed(seconds, &)
      Timeout.timeout(seconds, TimeoutError, "run timed out after #{seconds}s", &)
    end

    def execute(context, browser, recorder, lock)
      Executor.new(
        browser: browser, recorder: recorder, settings: context.settings, lock: lock, logger: @logger
      ).call(context.commands)
    end

    # Giving up on the cleanup is not a failure worth raising: the run has
    # already produced its answer, or its exception, and this is only the
    # tidying afterwards.
    def cleanup(recorder, browser)
      Timeout.timeout(CLEANUP_TIMEOUT) { unwind(recorder, browser) }
    rescue Timeout::Error
      @logger.warn("btape: cleanup did not finish within #{CLEANUP_TIMEOUT}s")
    end

    # stop and quit are reached again here after they have already run, which
    # is a no-op; the case that matters is the run failing before them. A
    # failure to unwind must not replace the exception on its way out, since
    # that is the one that says why the run failed — so it is logged, not
    # swallowed and not raised.
    def unwind(recorder, browser)
      recorder&.stop
    rescue StandardError => e
      @logger.warn("btape: could not stop the recorder: #{e.message}")
    ensure
      begin
        browser&.quit
      rescue StandardError => e
        @logger.warn("btape: could not quit the browser: #{e.message}")
      end
    end

    def encoder(settings)
      @gif_encoder || GifEncoder.for(settings)
    end

    def build_recorder(browser, context, lock)
      @recorder_class.new(
        browser,
        context.directory,
        interval: 1.0 / context.settings.framerate,
        mode: context.settings.capture_mode,
        on_frame: context.on_frame,
        max_frames: context.settings.max_frames,
        lock: lock
      )
    end

    def result(context, recorder)
      width, height = context.geometry
      Result.new(
        output_path: context.output_path,
        frame_paths: context.keep_frames ? recorder.paths.dup : [],
        named_frames: context.keep_frames ? recorder.named_paths.dup : {},
        frame_count: recorder.paths.length,
        width: width,
        height: height
      )
    end

    def open_browser(settings, geometry)
      width, height = geometry
      browser = @browser_factory.call(browser_options(settings, geometry))
      # window_size only ever reaches Chrome as a launch flag, so a browser we
      # connected to over ws_url keeps whatever size it was started with and
      # has to be resized over the wire instead.
      browser.resize(width: width, height: height) if settings.ws_url
      browser
    end

    def browser_options(settings, geometry)
      return { ws_url: settings.ws_url } if settings.ws_url

      { window_size: geometry }
    end
  end
end
