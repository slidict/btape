# btape

<p align="center">
  <img src="assets/logo.png" alt="btape logo" width="480">
</p>

`btape` is a small, VHS-inspired Ruby CLI that runs browser actions from a
`.tape` file and records them as an animated GIF. Ferrum controls Chromium
and captures PNG frames, and a pure-Ruby encoder produces the GIF. It
does not require Playwright, Selenium, ffmpeg, or an external service.

## Commands

```text
Output <path>
Viewport <width>x<height>
Set <name> <value>
Goto <url>
Click <CSS selector or text=Text>
Type <CSS selector> <text>
Press <key> [count]
Frame <CSS selector or main>
Evaluate <javascript>
WaitFor <CSS selector or text=Text> [duration]
WaitForJS <javascript> [duration]
Screenshot [name]
Sleep <number>ms|s
```

Arguments containing spaces must be quoted. Empty lines and lines beginning
with `#` are ignored. `Output` is required; `Viewport` defaults to `1280x720`.
Output paths are resolved relative to the tape file.

```text
Output demo.gif
Viewport 1280x720
Goto http://localhost:3000
Click "text=Login"
Type "#email" "demo@example.com"
Sleep 1s
```

`Evaluate` runs JavaScript in the current frame, which is how a tape reaches
an API the page exposes rather than clicking at it. `Frame` points the
commands that follow at an iframe, and `Frame main` returns to the page;
navigating returns to the page too, since the frame belonged to the page that
was left. `WaitFor` and `WaitForJS` poll instead of guessing at a `Sleep`.

`Screenshot` captures a frame there and then. With a name it also lands at a
predictable path, for picking one particular frame out of a run.

## Settings

`Set NAME VALUE` configures a run. Every setting can also be given on the
command line with `--set NAME=VALUE`, which wins over the tape, so one tape
can run in more than one place.

| Name | Default | Meaning |
| --- | --- | --- |
| `WsUrl` | — | Connect to a browser already running at this CDP url instead of launching one |
| `CaptureMode` | `interval` | `interval` records continuously; `manual` captures only where `Screenshot` says to |
| `Framerate` | `10` | Captures per second in interval mode |
| `FrameDelay` | `100ms` | How long each frame is shown in the GIF |
| `Loop` | `0` | Times to loop; 0 is forever |
| `Scale` | `1.0` | Scale the output down |
| `OutputWidth` | — | Output width in pixels; overrides `Scale` and keeps the aspect ratio |
| `Quantizer` | `adaptive` | `adaptive` picks the palette from the frames; `rgb332` uses a fixed one |
| `Timeout` | `120s` | Give up on the whole run after this |
| `WaitTimeout` | `10s` | Give up on a `WaitFor` or `WaitForJS` after this |
| `WaitInterval` | `100ms` | How often those two check |
| `WaitStable` | `1` | How many checks in a row must pass before a wait is satisfied |
| `MaxFrames` | `600` | Stop rather than record a hung page until the disk fills |

## Install and run

Chromium must be installed and discoverable by Ferrum. Then:

```sh
bundle install
bundle exec btape demo.tape
bundle exec rake spec
```

```text
Usage: btape [options] SCRIPT.tape

  --ws-url URL     Connect to a browser already running at this CDP url
  --set NAME=VALUE Override a setting, as a Set line would
  --frames-dir DIR Write the PNG frames here and keep them
  --verbose        Report each command on stderr as it runs
```

`BTAPE_WS_URL` is used when neither `--ws-url` nor `--set WsUrl=` is given.

### A browser running somewhere else

btape launches its own Chromium by default. Point it at one that is already
running — a `browserless`/`chrome` container, say — and no browser needs to be
in the image btape runs from:

```sh
btape --ws-url ws://chrome:3000 examples/thumbnails.tape
```

Each connection gets its own browser context, so concurrent runs against one
shared browser do not see each other. The viewport is applied over the wire,
since a browser that is already running cannot be told its window size at
launch.

### Frames, not just the GIF

Frames are normally written to a temporary directory and removed as the run
unwinds. `--frames-dir` keeps them:

```sh
btape --frames-dir frames examples/thumbnails.tape
```

## From Ruby

`Runner#run` returns a `Btape::Result`:

```ruby
commands = Btape::Parser.new.parse(File.read('deck.tape'))

result = Btape::Runner.new(logger: Rails.logger).run(
  commands,
  base_directory: File.dirname('deck.tape'),
  settings: { ws_url: ENV['CHROME_WS_URL'] },
  frames_directory: frames,
  on_frame: ->(path, index) { logger.debug("captured #{index}: #{path}") }
)

result.output_path            # where the GIF went
result.frame_count            # frames that went into it
result.frame_paths            # the frames, when frames_directory was given
result.named_frames['page-01'] # the frame a Screenshot named
```

Nothing has to touch the filesystem. Pass an IO to write the GIF into:

```ruby
buffer = StringIO.new(+''.b)
Btape::Runner.new.run(commands, base_directory: '.', output: buffer)

# `buffer.string` is the GIF. Hand it to whatever holds on to it — an Active
# Storage attachment on one of your own records, say:
deck = Deck.find(params[:id])
deck.animation.attach(io: StringIO.new(buffer.string), filename: 'deck.gif')
```

or use the encoder on its own, with PNG paths or ChunkyPNG images:

```ruby
Btape::GifEncoder.new(delay: 150, width: 640).encode(frame_paths) # => String
```

## Container development with dip or wip

The development image contains Ruby and Chromium.

```sh
dip provision
dip test
dip demo

wip up
wip dispatch demo
wip dispatch btape examples/demo.tape
```

`examples/demo.tape` drives a small static page bundled at
`examples/demo_app.html`, so the demo is self-contained and needs no other
service running. Edit the tape (or point `Goto` at a different URL) to record
something else. `examples/thumbnails.tape` shows the other shape of run: one
frame per page of a deck, against a browser running elsewhere.

## Limitations

The palette is chosen from the frames being encoded, which tracks gradients
and text edges far more closely than the fixed RGB332 palette earlier versions
used — but banding compresses well and fidelity does not, so the files are
larger than they were. `Set Scale` or `Set OutputWidth` are the levers to pull
back; identical consecutive frames are already collapsed into one held for
longer. `Set Quantizer rgb332` restores the old palette.

The first matching element is used for `Click` and `Type`.

## Upgrading to 0.2

`Runner#run` returns a `Btape::Result` rather than the output path. Read
`result.output_path` where the path was used before.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
for the development setup, PR conventions, and how releases are generated.
This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE)
