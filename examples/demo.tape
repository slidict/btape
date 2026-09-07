# The demo recorded in the README: a login form on a static page bundled with
# the repository, so nothing else has to be running.
#
# The path below is where the development container mounts the checkout
# (`dip demo`, `wip dispatch demo`). Running this on the host instead? Point
# Goto at your own copy — file:///path/to/btape/examples/demo_app.html.

Output demo.gif
Viewport 1280x720

Goto file:///app/examples/demo_app.html
Sleep 500ms

Click "text=Login"
Sleep 300ms
Type "#email" "demo@example.com"
Type "#password" "password"
Click "text=Sign in"
Sleep 2s
