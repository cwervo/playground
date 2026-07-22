# Surfboard 🏄

A single-window iPadOS 27 app for capturing **clips** — anything you can put on
the iOS clipboard/keyboard: text, links, images, video, audio and arbitrary
files. Built from scratch with **only Apple frameworks** (SwiftUI, UIKit,
Foundation, UniformTypeIdentifiers, CoreText). No third-party dependencies.

## The three panels

```
┌────────────┬───────────────────────────────┬──┐
│            │                               │  │
│  Gallery   │           Editor              │S │  ← Settings drawer
│  (20% ×    │   double-tap to paste,        │E │    peeks 10%, drag it
│   90%,     │   or type & Append            │T │    open to reveal the
│  centred)  │                               │T │    full settings panel
│            │                               │… │
└────────────┴───────────────────────────────┴──┘
```

1. **Gallery** (left) — 20% of the width, 90% of the height, vertically
   centred. A scrollable mini-gallery of every saved clip with a type icon or
   image thumbnail, kind label and relative timestamp. Long-press a cell to
   delete it.
2. **Editor** (middle) — type with the keyboard and press **Append** to save
   the text as a clip, or **double-tap** the box to be offered a paste from the
   clipboard (captured straight into the gallery, or dropped into the editor).
3. **Settings** (right) — a drawer that only shows a 10%-wide tab by default.
   Tap or drag it open to reveal all settings, including the guarded
   **Delete All Data** flow: it takes two taps and a **red confirmation** so you
   never nuke your Surfboard data by accident.

## Design system

| Token        | Value                                             |
|--------------|---------------------------------------------------|
| Dominant     | Peach (`#FFD9B8`, with `#FFEBDA` / `#FFC79A`)      |
| Accent       | `#1010FF` electric blue                           |
| Title / body | IBM Plex Sans                                     |
| Code / instr.| IBM Plex Mono                                     |

The IBM Plex font files aren't committed (see
`Surfboard/Resources/Fonts/README.md`); the app falls back to the system sans
and monospaced faces automatically if they're absent, and picks up the real
Plex faces as soon as you drop them in.

## Build & run

Open `Surfboard.xcodeproj` in Xcode 27+ and run on an iPad (or the iPad
simulator). The project uses a file-system-synchronized group, so any file
added under `Surfboard/` is compiled automatically — no `.pbxproj` surgery
needed.

## Project layout

```
Surfboard/
├── Surfboard.xcodeproj
└── Surfboard/
    ├── SurfboardApp.swift        App entry + font registration
    ├── Info.plist
    ├── Models/
    │   ├── Clip.swift            The clip value type + kinds
    │   └── ClipStore.swift       Persistence + clipboard capture
    ├── Theme/
    │   └── Theme.swift           Colours + IBM Plex typography
    ├── Views/
    │   ├── ContentView.swift     Three-panel layout + settings drawer
    │   ├── GalleryView.swift     Left mini-gallery
    │   ├── EditorView.swift      Middle capture surface
    │   └── SettingsPanel.swift   Right settings drawer + danger zone
    ├── Resources/Fonts/          Drop IBM Plex .ttf files here
    └── Assets.xcassets/          Accent colour, launch colour, app icon
```
