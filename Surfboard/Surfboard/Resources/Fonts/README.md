# Fonts

Surfboard's type system uses **IBM Plex Sans** (titles + body) and
**IBM Plex Mono** (code + app instructions).

These are open-source fonts (SIL Open Font License) from IBM, but the binary
font files are **not** committed here to keep the repo free of third-party
blobs. The app still builds and runs without them — `Theme.swift` transparently
falls back to the system sans / monospaced faces if the Plex files are absent.

## To use the real IBM Plex fonts

1. Download the families from <https://github.com/IBM/plex/releases>
   (or `brew install --cask font-ibm-plex-sans font-ibm-plex-mono`).
2. Copy exactly these files into this folder:

   ```
   IBMPlexSans-Regular.ttf
   IBMPlexSans-Medium.ttf
   IBMPlexSans-SemiBold.ttf
   IBMPlexSans-Bold.ttf
   IBMPlexMono-Regular.ttf
   IBMPlexMono-Medium.ttf
   ```

3. Make sure they are members of the **Surfboard** target (they are picked up
   automatically by the file-system-synchronized project group, and are also
   registered programmatically at launch by `FontRegistrar`).

The PostScript face names the app looks up are `IBMPlexSans`,
`IBMPlexSans-Medium`, `IBMPlexSans-SemiBold`, `IBMPlexSans-Bold`,
`IBMPlexMono` and `IBMPlexMono-Medium`.
