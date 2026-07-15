# How the folk-cwe programs work

## email-piles.folk — data flow

```mermaid
flowchart TD
    subgraph disk["~/folk-data/user-programs/folk-cwe/"]
        ENV[".env<br/>GMAIL_ACCESS_TOKEN=ya29...<br/><i>(optional)</i> GMAIL_CLIENT_ID /<br/>GMAIL_CLIENT_SECRET / GMAIL_REFRESH_TOKEN"]
    end

    CLOCK(["When the clock time is /t/"]) --> GUARD{"time since last fetch<br/>≥ interval?<br/>(5 s unconfigured,<br/>20 s on error, 300 s ok)"}
    GUARD -- no --> CLOCK
    GUARD -- yes --> READ["epReadEnv — parse .env"]
    ENV -.-> READ
    READ --> CREDS{"any credentials?<br/>(GMAIL_ACCESS_TOKEN, legacy<br/>GOOGLETOKEN, or refresh trio)"}

    CREDS -- no --> SETUP["state = setup:<br/>'no token found'"]
    CREDS -- yes --> FETCH["epFetchEmails"]

    subgraph gmail["Gmail REST API (via curl)"]
        LIST["GET /users/me/messages?maxResults=12"]
        META["GET /messages/{id}?format=metadata<br/>→ Subject header + internalDate<br/>(bodies never downloaded)"]
        REFRESH["POST oauth2.googleapis.com/token<br/>grant_type=refresh_token"]
    end

    FETCH --> LIST
    LIST -- "401 (token expired)" --> REFRESH
    REFRESH -- "new access token, retry" --> LIST
    REFRESH -- "no refresh creds" --> ERR["state = error:<br/>'token expired…'"]
    LIST -- 200 --> META
    META --> OK["state = ok +<br/>emails {epoch subject}…"]

    SETUP --> COMMIT[["Commit → Claim $this has email state …<br/>(persists across frames)"]]
    ERR --> COMMIT
    OK --> COMMIT
```

## What gets projected — the two `When`s that react to the state

```mermaid
flowchart TD
    STATE[("Claim:<br/>$this has email state /state/")]

    STATE --> WHENBAD(["When state + clock time<br/>(status ≠ ok)"])
    WHENBAD --> FLASH["outline flashes<br/>darkgreen ↔ green at 2 Hz<br/>(int(t·2) % 2)"]
    WHENBAD --> INSTR["page labelled with setup<br/>instructions: .env path,<br/>GMAIL_ACCESS_TOKEN=…,<br/>OAuth playground steps"]

    STATE --> WHENOK(["When state + page region<br/>(status = ok)"])
    WHENOK --> SORT["sort emails newest-first,<br/>deal by received date:<br/>≥ midnight → today<br/>≥ now−7d → this week<br/>else → older"]
    SORT --> DRAW["for each pile (≤ 5 pages,<br/>drawn bottom-up so newest<br/>lands on top):<br/>• opaque white rect 136×176 px<br/>(8.5×11 @ ~16 px/in)<br/>• gray edge, fanned 16 px/page<br/>• center label: subject + date<br/>• header: pile name (count)"]
    WHENOK --> GREEN["steady green outline +<br/>'12 recent emails / today 3…'"]

    DRAW --> TABLE[/"projector: 3 piles below the page<br/>today · this week · older"/]
```

## camera-ocr.folk — slice → HTML, OCR everything in frame

```mermaid
sequenceDiagram
    participant P as camera-ocr.folk<br/>(page on the table)
    participant F as Folk web server
    participant B as Browser at /frame-ocr<br/>(laptop/phone)
    participant T as Tesseract.js<br/>(in-browser, from CDN)

    P->>F: Wish the web server handles route "/frame-ocr"
    B->>F: GET /frame-ocr
    F-->>B: HTML page
    loop every 1.5 s (double-buffered, no flicker)
        B->>F: GET /camera?nocache=…
        F-->>B: frame → contain-fit background layer
    end
    loop every ~4 s
        B->>B: draw current frame to canvas
        B->>T: worker.recognize(canvas)
        T-->>B: text + word boxes
        B->>B: overlay green word boxes,<br/>full text in bottom-left panel
        B->>F: FolkWS ws.hold(base64-tunneled Tcl)
        F->>P: Claim: the camera sees text /text/
        P->>P: When /someone/ claims the camera sees text →<br/>label the page (any program can react)
    end
```

## Outline color = connection status

```mermaid
stateDiagram-v2
    [*] --> Flashing : program placed,<br/>no working token
    Flashing --> Steady : .env written with valid token<br/>(checked every 5 s)
    Steady --> Flashing : token expired and<br/>self-refresh unavailable
    Steady --> Steady : self-refresh on 401<br/>(refresh trio in .env)

    Flashing : Flashing darkgreen/green — Gmail not granted, instructions projected
    Steady : Steady green — connected, piles drawn, refetch every 5 min
```
