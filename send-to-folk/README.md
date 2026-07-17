# Send To Folk

A macOS menu-bar app that adds a global **"Send To Folk"** entry to the OS
Services (right-click) menu. Anything selectable in the OS — text, images,
files of any type or extension, without filters — gets captured as a
timestamped `.folk` file on `~/Desktop`.

## What it writes

Each capture creates:

```
~/Desktop/DDMMYY/HHMMSSmmmAM.folk    # the lead .folk file (ms + AM/PM)
~/Desktop/DDMMYY/HHMMSSmmmAM/        # assets folder (only when needed)
```

The `.folk` file contains one line per captured item:

| Input | Line written |
|---|---|
| Image (file or copied image data) | `Wish $this displays image ~/Desktop/$DATE/$TIME/UUID.png` — image saved alongside |
| Text | `Wish $this is labelled "$TEXT"` |
| Any other file | `Claim $this has unknown data $PATHTOFILE` — a copy of the file is saved alongside |

Text is Tcl-escaped (`"`, `\`, `$`, `[`, `]`) so the label survives Folk's
Tcl evaluation.

## Build & install (on a Mac)

```sh
./build.sh
cp -R build/SendToFolk.app /Applications/
open /Applications/SendToFolk.app
```

The app runs as a menu-bar item (paper-plane icon) with no Dock presence.
On first launch macOS registers its service; if **Send To Folk** doesn't
show up in context menus yet, run:

```sh
/System/Library/CoreServices/pbs -update
```

or log out and back in.

## Use

- **Selected text** anywhere: right-click → Services → **Send To Folk**
  (in many apps it appears directly in the context menu).
- **Files in Finder**: select any files, right-click → Services →
  **Send To Folk**. Works on any file type; images are recognized and
  saved as displayable assets, everything else is copied and claimed as
  unknown data.
- **Copied images** (e.g. "Copy Image" in a browser): select/copy, then
  invoke the service from an app that puts image data on the service
  pasteboard.

You can also bind a global keyboard shortcut to the service in
**System Settings → Keyboard → Keyboard Shortcuts → Services**.

A soft "Pop" sound confirms each capture. The menu-bar icon has an
**Open Today's Folder** shortcut to jump to `~/Desktop/DDMMYY/`.
