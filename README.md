# btape

`btape` is a small, VHS-inspired Ruby CLI that runs browser actions from a
`.tape` file and records them as an animated GIF. Ferrum controls Chromium
and captures PNG frames, and a pure-Ruby encoder produces the GIF. It
does not require Playwright, Selenium, ffmpeg, or an external service.

## Commands

```text
Output <path>
Viewport <width>x<height>
Goto <url>
Click <CSS selector or text=Text>
Type <CSS selector> <text>
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

## Install and run

Chromium must be installed and discoverable by Ferrum. Then:

```sh
bundle install
bundle exec btape demo.tape
bundle exec rake spec
```

The recording interval is 100 ms (10 fps). Temporary PNG frames are removed
after a successful run. They are also isolated in the system temporary
directory and cleaned when an error unwinds the run.

## Container development with dip or wip

The development image contains Ruby and Chromium. Both wrappers expose the
same `test`, `demo`, `bundle`, and `bash` commands:

```sh
dip provision
dip test
dip demo

wip provision
wip test
wip demo
```

The example expects the demo application on port 3000 of the container host.
On Linux, add an appropriate `host.docker.internal` host mapping if Docker does
not provide one automatically. You can also edit `examples/demo.tape` to point
at another local URL.

## MVP limitations

The GIF encoder uses a fixed 256-colour RGB332 palette to stay dependency-light.
This favors portability over photographic colour fidelity and file size. The
first matching element is used for `Click` and `Type`.

