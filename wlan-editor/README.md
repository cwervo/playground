# wlan-editor

A tiny server you run on your laptop so that everyone else on the same WiFi can
open your IP address in a browser and **edit one HTML page together**.

No build step, no npm install, no internet needed — just Node.

```
cd wlan-editor
node server.js
```

```
  wlan-editor is up
  saving to /Users/you/playground/wlan-editor/page.json

  Tell people on this WiFi to open:
    http://10.0.14.92:8080   [en0]

  On this laptop:  http://localhost:8080
```

Read out that `http://10.0.14.92:8080` line. Anyone on the school WiFi who types
it in is now editing the same page as you.

## What people can do

- **Click any text and type.** Everyone sees it as you go.
- **`</>` on a block** — edit that block's raw HTML. Write `<img>`, `<table>`,
  `<marquee>`, whatever.
- **`Source`** — rewrite the entire page's HTML in one textarea and push it to
  everyone.
- **`<style>` works.** A block that's just a `<style>` shows up as a dashed chip
  (it renders nothing, so otherwise it would look like a hole in the page), and
  its CSS applies to the page for everyone.
- **`Preview`** — the page on its own with no editor chrome. `<script>` tags run
  here; they deliberately don't run inside the editor, so nobody's stray
  `while(true)` freezes everyone's editing.
- **`Save file`** — download the page as a normal `.html` file.
- **`Undo`** — undoes the last change *anyone* made. Shared undo, so it's the
  fix when someone deletes the whole page.

Coloured pills along the top show who's here; the coloured outline shows which
block each person is in.

## Options

```
node server.js --port 3000            # if 8080 is taken
node server.js --file class-3b.json   # keep several pages side by side
node server.js --code trilobite       # require a code word to join
```

`--port` also reads `$PORT`, `--code` also reads `$ROOM_CODE`.

The page is saved to `page.json` as people type. Killing the server and starting
it again picks up exactly where everyone left off, and browsers that were open
reconnect by themselves.

## If people can't reach you

- **Same network?** Phones on `Guest` and laptops on `Students` usually can't
  see each other, even in the same room.
- **Client isolation.** Some school access points block laptop-to-laptop traffic
  entirely. Nothing you can do from this side; a phone hotspot is the usual
  workaround.
- **Firewall.** macOS asks "allow incoming connections?" the first time — say
  yes. On Linux: `sudo ufw allow 8080`.
- **Wrong address.** If several are listed, the one on the same subnet as
  everyone else is the right one (usually `192.168.x.x` or `10.x.x.x`).

## How the merging works

The page is a list of **blocks** (roughly, one top-level element each). Edits are
scoped to a single block and the last write to a block wins.

So two people editing different paragraphs never clobber each other — which is
almost always what's happening. Two people inside the *same* paragraph will
fight over it, and the coloured outline is there to make that visible before it
happens. That is the honest limit of this design: it is not a CRDT, and it is not
trying to be. For a room of people each working on their own bit of a page, it
holds up fine.

`Source` and `Undo` replace the whole document at once, so they'll interrupt
anyone mid-sentence — that's why both are deliberate button presses.

## Trust model — read this before using it

**Anyone who can reach the port can edit the page, and there is no history of
who wrote what.** That's the entire point of the tool, but it means:

- Whatever HTML someone types is served to everyone else. `--code` is a speed
  bump for a classroom, not security.
- Run this on a network you trust, for as long as you need it, then stop it.
  Don't port-forward it to the internet.
- `Preview` runs whatever `<script>` is on the page. Only open it if you'd trust
  the room to run code on your laptop's browser.

## Under the hood

- `server.js` — everything server-side. Node standard library only.
  Browser → server edits are `POST /api/op`; server → browser updates are one
  Server-Sent Events stream per person (`GET /api/stream`). SSE rather than
  WebSockets so there's nothing to install.
- `public/` — the editor. Plain HTML/CSS/JS, no framework.
