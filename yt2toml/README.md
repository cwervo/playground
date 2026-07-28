# yt2toml

Parse a YouTube playlist into one `$VideoTitle.toml.txt` file per video,
containing the video URI, title, YouTube metadata, and the full caption
transcript with timestamps aligned to femtosecond fixed-point encoding via a
Go↔C++ FFI (cgo) core.

## Usage

```sh
cd yt2toml
go build -o yt2toml .
./yt2toml -out transcripts -lang en 'https://youtube.com/playlist?list=PL...'
```

## What it does

1. Extracts the playlist ID from the URL.
2. Lists every video via YouTube's InnerTube `browse` endpoint (the JSON API
   the web player uses — no API key), following pagination continuations.
3. For each video, fetches the player response for metadata (title, channel,
   duration, view count, keywords, description) and the caption track list.
4. Downloads the preferred caption track as `json3` timedtext and flattens it
   into cues.
5. Runs every cue interval through `align/`, a C++17 fixed-point aligner
   called through cgo, producing exact femtosecond-resolution timestamps
   (`seconds` + `femtoseconds` integer pair, plus a `"S.FFFFFFFFFFFFFFF"`
   decimal string).
6. Writes a TOML document per video, named after the sanitized title:
   `Building a Tiny Compiler Part 1.toml.txt`.

## Output shape

```toml
[video]
id = "..."
url = "https://www.youtube.com/watch?v=..."
title = "..."
channel = "..."
length_seconds = 612
view_count = 12345

[playlist]
id = "PL..."
index = 1

[transcript]
language = "en"
kind = "asr"
source = "youtube-timedtext-json3"

[[transcript.cue]]
text = "hello and welcome"
start_ms = 1240
end_ms = 3980
start_fs = "1.240000000000000"
end_fs = "3.980000000000000"
start_seconds = 1
start_femtoseconds = 240000000000000
end_seconds = 3
end_femtoseconds = 980000000000000
```

## Honest precision note

YouTube reports cue timing in **milliseconds**. The C++ aligner encodes those
measurements exactly at femtosecond fixed-point resolution (no float error),
but the underlying measurement resolution is still 1 ms. True sub-millisecond
forced alignment (e.g. [gentle](https://github.com/lowerquality/gentle))
requires downloading the audio itself, which is out of scope for this tool
(and blocked in the environment it was built in).

## Tests

`go test ./...` runs an end-to-end test against a fixture InnerTube server
(see `testdata/`), covering playlist pagination, metadata extraction,
transcript flattening, FFI alignment, and TOML round-tripping.
