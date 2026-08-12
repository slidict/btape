# One frame per page of a slide deck, against a browser running elsewhere.
#
#   btape --frames-dir frames examples/thumbnails.tape
#
# Every Set line here can also be given on the command line, so the same tape
# runs against a local browser (drop --ws-url) or a remote one:
#
#   btape --ws-url ws://chrome:3000 examples/thumbnails.tape

Output deck.gif
Viewport 1280x720

Set WsUrl ws://chrome:3000
# Capture only where this tape says to, so a twenty page deck is twenty
# frames rather than the several hundred an interval recording would take.
Set CaptureMode manual
Set FrameDelay 1.5s
# The page reports when it has finished drawing, but sets the flag before it
# has settled, so ask for the answer to hold rather than trusting one reading.
Set WaitStable 5
Set WaitTimeout 15s

# The browser resolves this URL, not btape, so a remote browser needs a host
# it can reach: `localhost` there means the browser's own container. Against a
# local browser, `http://localhost:3000/decks/1` is the same page.
Goto http://app:3000/decks/1

# The deck renders inside an iframe, so reach into it for both the readiness
# flag and the navigation.
WaitFor iframe#preview
Frame iframe#preview

WaitForJS "window.__DECK_READY__ === true"
Screenshot page-01

Evaluate "Reveal.slide(1, 0)"
WaitForJS "window.__DECK_READY__ === true"
Screenshot page-02

Evaluate "Reveal.slide(2, 0)"
WaitForJS "window.__DECK_READY__ === true"
Screenshot page-03
