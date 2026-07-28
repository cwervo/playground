# yt-playlist-transcriber

Go pipeline that turns a YouTube playlist into one `$Title.toml.txt` file per
video, containing full YouTube metadata plus a word-level forced-alignment
transcript.

## Pipeline

1. **yt-dlp** (`--flat-playlist -J`) — enumerate the playlist into video IDs/titles.
2. **yt-dlp** per video — full metadata JSON, English captions (manual or
   auto-generated, VTT → plain text), and audio as 16 kHz mono WAV.
3. **Gentle** ([lowerquality/gentle](https://github.com/lowerquality/gentle)) —
   forced alignment of the caption text against the audio. Gentle's alignment
   engine is Kaldi (C++); the server exposes it over HTTP, which serves as the
   Go↔C++ FFI boundary without cgo.
4. TOML output: `[video]`, `[playlist]`, `[[transcript.words]]` (word, start,
   end, case), and a `[transcript.plain]` full-text block.

## Precision note

Timestamps are seconds with millisecond formatting. Gentle/Kaldi aligns on
10 ms MFCC frames — that is the real resolution floor of forced alignment.
"Femtosecond" alignment is not a thing for audio: the waveform itself is
sampled at ~22.7 µs intervals (44.1 kHz), and phoneme boundaries are not
physically defined more finely than a frame.

## Usage

```sh
# prerequisites
pip install yt-dlp            # + ffmpeg on PATH
docker run -p 8765:8765 lowerquality/gentle

go run . -out out 'https://www.youtube.com/playlist?list=<PLAYLIST_ID>'

# metadata only, no audio/alignment:
go run . -skip-align 'https://www.youtube.com/playlist?list=<PLAYLIST_ID>'

# flags: -out DIR, -audio DIR, -gentle URL, -limit N, -skip-align
```

## Testing

`go test ./...` — parsers (playlist JSON, Gentle JSON, VTT) and the TOML
encoder are covered with fixtures in `testdata/`; no network needed.
