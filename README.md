# Swab

*swab — to mop the deck of a ship.*

A menu-bar utility in the spirit of DeskMop: one click stages a spotless
desktop for screenshots and screen recordings — icons gone, wallpaper covered
by a clean color, resolution set, your app's window placed just so — and one
click puts every last thing back exactly the way it was. Swab snapshots the
current state to disk *before* it touches anything, so even a crash can't
leave your desk in costume.

## Staging

- **Hide desktop icons** — flips Finder's `CreateDesktop` preference and
  relaunches Finder (that's the only way; Finder reads the key at launch).
  The prior value — including "no value at all" — is recorded and written
  back verbatim on Restore.
- **Clean backdrop** — a borderless, click-through window per display, layered
  just above the desktop picture and below the icon layer. It shows up in
  recordings on purpose; your real wallpaper setting is never modified.
  Four fills: one of five presets (Graphite, Midnight, Ocean, Dawn, Paper), a
  solid color, a two-stop gradient, or an image. Editing the fill while staged
  updates live.
- **Set resolution** — enumerates each display's usable modes (deduped, HiDPI
  preferred), highlights 1920 × 1080 and 1280 × 800 as recording-friendly, and
  switches every display you targeted inside a *single* display-configuration
  transaction, so the screens reconfigure together instead of flickering one
  after another. Displays left on "Don't change" are untouched. The exact
  original modes return on Restore.
- **Place a window** — pick any running app and a frame (centered 16:10,
  centered 16:9, or golden-ratio left); Swab moves and sizes its front window
  via the Accessibility API and restores the original frame afterward. The
  frame you pick is remembered per app, so choosing that app again recalls it.
- **Focus pairing** — macOS still gives apps no supported way to set a Focus
  mode, and Swab won't pretend otherwise. What it *can* do is run two
  Shortcuts you build (using the Shortcuts app's "Set Focus" action) through
  the supported `shortcuts` CLI: one when staging, one when restoring. If the
  shortcuts aren't there, the step is skipped with a message rather than
  failing quietly.
- **Stage / Restore** — the big button runs the enabled steps in order;
  Restore undoes them in reverse. Both also live in the menu-bar menu, so you
  can restore even with the window closed. Quitting Swab auto-restores, and
  the pre-stage snapshot is persisted to
  `~/Library/Application Support/Swab/snapshot.json` so a crashed session can
  still be restored on next launch.

## Capture

- **Screenshots and recordings** — take a still or start a screen recording
  from Swab or its menu, without breaking the staged setup. Files land in
  `~/Pictures/Swab` rather than the Desktop, which is usually hidden while
  you're staged. Both go through the system `screencapture` tool, so the
  formats and the permission prompt are the familiar ones. Restoring stops a
  recording that's still running.
- **Cursor and clicks** — the pointer is left out of captures unless you ask
  for it. Clicks can be highlighted with an expanding ring drawn in a
  click-through overlay: it shows up in the recording without changing where
  your clicks actually land.

## Automation

- **Presets** — save the whole setup under a name (steps, backdrop,
  per-display resolutions, placement, timer) and load it again in one click,
  from the window or the menu-bar Presets submenu. Loading a preset configures
  Swab but deliberately doesn't stage, so you can look before you leap.
- **Global hotkey** — one combination that stages when the desk is clear and
  restores when it's staged. Registered through Carbon's `RegisterEventHotKey`,
  which needs no extra permission; if another app already owns the combination,
  Swab says so instead of binding nothing.
- **Auto-restore timer** — stage for a set number of minutes and let Swab put
  everything back on its own. The countdown shows in the menu bar while it
  runs, and can be extended without restarting it.
- **Command line** — installs a small `swab` script that drives the app
  through its `swab://` URL scheme:

  ```
  swab stage
  swab restore
  swab toggle
  swab shot
  swab record        # swab stop to finish
  swab preset "Demo"
  ```

  It installs to `/usr/local/bin` when that's writable and `~/.local/bin`
  otherwise; Swab tells you which, and whether it's on your `PATH`.

## Build

```
./make-app.sh
```

Builds a release binary, generates the icon, assembles `Swab.app`, installs it
to /Applications, and launches it.

## Permissions

- **Accessibility** — required only for the "Place a window" step (moving
  another app's window uses `AXUIElementSetAttributeValue`). Swab asks the
  first time you need it and degrades gracefully — every other step works
  without it.
- **Screen Recording** — required only for the capture features, and prompted
  for by macOS the first time you take a shot or start a recording.

Heads-up rather than a permission: hiding desktop icons **restarts Finder**
when staging and again when restoring. Finder windows will briefly close and
reopen.

## Not yet

- **Menu-bar tidying** — macOS offers no supported way to rearrange or hide
  third-party status items from another app, and the auto-hide-menu-bar
  defaults keys behave inconsistently across recent macOS releases. Rather
  than ship a flaky toggle, Swab leaves the menu bar alone for now.
- **Setting Focus directly** — still blocked by the OS. The Shortcuts pairing
  above is the honest workaround, not a claim that Swab can flip Focus itself.
