# Swab

*swab — to mop the deck of a ship.*

A menu-bar utility in the spirit of DeskMop: one click stages a spotless
desktop for screenshots and screen recordings — icons gone, wallpaper covered
by a clean color, resolution set, your app's window placed just so — and one
click puts every last thing back exactly the way it was. Swab snapshots the
current state to disk *before* it touches anything, so even a crash can't
leave your desk in costume.

## Features

- **Hide desktop icons** — flips Finder's `CreateDesktop` preference and
  relaunches Finder (that's the only way; Finder reads the key at launch).
  The prior value — including "no value at all" — is recorded and written
  back verbatim on Restore.
- **Clean backdrop** — a borderless, click-through window per display, layered
  just above the desktop picture and below the icon layer, filled with one of
  five presets (Graphite, Midnight, Ocean, Dawn, Paper). It shows up in
  recordings on purpose; your real wallpaper setting is never modified.
  Swapping presets while staged updates live.
- **Set resolution** — enumerates the main display's usable modes (deduped,
  HiDPI preferred), highlights 1920 × 1080 and 1280 × 800 as
  recording-friendly, and switches inside a display-configuration transaction.
  The exact original mode returns on Restore.
- **Place a window** — pick any running app and a frame (centered 16:10,
  centered 16:9, or golden-ratio left); Swab moves and sizes its front window
  via the Accessibility API and restores the original frame afterward.
- **Do Not Disturb reminder** — macOS gives apps no supported way to flip
  Focus modes, so Swab shows an honest reminder chip with a shortcut to Focus
  settings instead of a toggle that lies.
- **Stage / Restore** — the big button runs the enabled steps in order;
  Restore undoes them in reverse. Both also live in the menu-bar menu, so you
  can restore even with the window closed. Quitting Swab auto-restores, and
  the pre-stage snapshot is persisted to
  `~/Library/Application Support/Swab/snapshot.json` so a crashed session can
  still be restored on next launch.

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

Heads-up rather than a permission: hiding desktop icons **restarts Finder**
when staging and again when restoring. Finder windows will briefly close and
reopen.

## Not yet

- **Menu-bar tidying** — macOS offers no supported way to rearrange or hide
  third-party status items from another app, and the auto-hide-menu-bar
  defaults keys behave inconsistently across recent macOS releases. Rather
  than ship a flaky toggle, Swab leaves the menu bar alone for now.
- Per-display resolution control (currently the main display only).
- Automatic Do Not Disturb (blocked by the OS; the reminder chip stays honest).
