# folk-cwe user programs

Two Folk programs that live together:

- **`email-piles.folk`** — projects a *sense* of your Gmail inbox as three
  piles of overlapping, opaque 8.5"×11" pages (subject + received date on
  each page's center label). Not an inbox replacement.
- **`camera-ocr.folk`** — serves `/frame-ocr`, a browser page that shows
  `/camera` contain-fit as its background layer and OCRs everything in the
  frame with Tesseract.js, claiming the recognized text back onto the table.

Config lives in **`~/folk-data/user-programs/folk-cwe/.env`** (copy
`.env.example` there).

## Why the variable is called `GMAIL_ACCESS_TOKEN` (not `GOOGLETOKEN`)

The thing you paste is specifically a **Gmail OAuth2 access token** — a
short-lived bearer credential scoped to the Gmail API. It is not a Google
API key and not a general-purpose "Google token", and naming it precisely
matters because the failure mode of pasting the wrong kind of credential is
a confusing `401`. (`GOOGLETOKEN` is still accepted as a legacy alias.)

## Quick setup (~2 minutes, token expires after ~1 hour)

1. Open <https://developers.google.com/oauthplayground>.
2. In **Step 1**, find **Gmail API v1** and tick
   `https://www.googleapis.com/auth/gmail.readonly` (read-only is all the
   program needs — don't grant more).
3. Click **Authorize APIs** and sign in with your Gmail account.
4. In **Step 2**, click **Exchange authorization code for tokens**.
5. Copy the **Access token** value into the `.env`:

   ```
   mkdir -p ~/folk-data/user-programs/folk-cwe
   printf 'GMAIL_ACCESS_TOKEN=ya29.PASTE_IT_HERE\n' > ~/folk-data/user-programs/folk-cwe/.env
   chmod 600 ~/folk-data/user-programs/folk-cwe/.env
   ```

Within ~5 seconds the page's flashing dark-green/green outline should turn
steady green and the piles appear. When the token expires (~1 hour) the
outline starts flashing again — paste a fresh one, or do the durable setup:

## Durable setup (refreshes itself, no more hourly pasting)

1. In <https://console.cloud.google.com> create a project (any name).
2. **APIs & Services → Library** → enable **Gmail API**.
3. **APIs & Services → OAuth consent screen** → External → add your own
   address as a **test user**.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**
   → type **Web application** → add
   `https://developers.google.com/oauthplayground` as an authorized
   redirect URI. Note the client ID and client secret.
5. Back in the OAuth playground, click the ⚙️ gear icon → tick **Use your
   own OAuth credentials** → paste the client ID/secret, then repeat the
   quick-setup authorize/exchange steps.
6. This time also copy the **Refresh token** and fill in all of:

   ```
   GMAIL_CLIENT_ID=....apps.googleusercontent.com
   GMAIL_CLIENT_SECRET=...
   GMAIL_REFRESH_TOKEN=1//...
   ```

   With those present, `email-piles.folk` renews its own access token
   whenever Gmail answers `401`, so the piles just keep working.

**Security notes:** the `.env` grants read access to your entire inbox —
keep it `chmod 600`, never commit it, and you can revoke access any time at
<https://myaccount.google.com/permissions>.

## How email-piles works

- Every 5 minutes (every 5 s while unconfigured, so it lights up right
  after you write the `.env`) it lists your 12 most recent messages and
  fetches each one's `Subject` header + `internalDate`
  (`format=metadata` — message bodies are never downloaded).
- Emails are dealt into three piles below the page: **today**,
  **this week**, **older**. Each pile shows up to 5 opaque letter-sized
  pages, newest on top, fanned so you can see the stack depth; each page's
  center label is the subject (truncated) and the received date.
- Outline language: **flashing dark green/green** = Gmail not granted yet
  (or token expired/failed); **steady green** = connected.
- Tunables are at the top of the drawing `When`: `pageW`/`pageH` (size),
  `fanStep` (peek distance), `maxShown`, `pileGap`.
- The fetch is synchronous `curl`, so the program pauses a few seconds
  while refreshing. Fine for a sense-making tool; make it async if it ever
  bothers you.

## How camera-ocr works

- Put the page on the table, then open `http://<folk-host>/frame-ocr` from
  a laptop or phone on the same network.
- `/camera` renders contain-fit as the page background (double-buffered
  re-fetch every 1.5 s for still-frame endpoints; untick **re-fetch frame**
  if your `/camera` is an MJPEG stream and let it play natively).
- Every ~4 s the current frame is OCR'd **in the browser** with
  Tesseract.js (CDN — the browsing device needs internet once; nothing is
  installed on the Folk machine). Word boxes are overlaid on the video and
  the full text shows in the bottom-left panel.
- The text is also held into the Folk database as
  `the camera sees text /text/`, so any other program on the table can
  react to what the camera reads. `camera-ocr.folk` labels itself with the
  latest reading as a demo.
