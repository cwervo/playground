// yt2toml: parse a YouTube playlist into per-video $Title.toml.txt files
// containing URI, title, YouTube metadata, and the full caption transcript
// with femtosecond fixed-point aligned timestamps (Go↔C++ FFI, see align/).
//
// Usage:
//
//	yt2toml -out transcripts 'https://youtube.com/playlist?list=PL...'
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"
)

func main() {
	outDir := flag.String("out", ".", "directory to write .toml.txt files into")
	lang := flag.String("lang", "en", "preferred caption language code")
	flag.Parse()
	if flag.NArg() != 1 {
		fmt.Fprintln(os.Stderr, "usage: yt2toml [-out dir] [-lang en] <playlist-url-or-id>")
		os.Exit(2)
	}
	if err := run(NewClient(), flag.Arg(0), *outDir, *lang, os.Stderr); err != nil {
		log.Fatal(err)
	}
}

func run(c *Client, playlistArg, outDir, lang string, logw *os.File) error {
	id, err := ExtractPlaylistID(playlistArg)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}
	items, playlistTitle, err := c.FetchPlaylist(id)
	if err != nil {
		return fmt.Errorf("fetch playlist %s: %w", id, err)
	}
	if len(items) == 0 {
		return fmt.Errorf("playlist %s: no videos found (private, empty, or invalid ID?)", id)
	}
	fmt.Fprintf(logw, "playlist %q: %d videos\n", playlistTitle, len(items))

	for _, item := range items {
		meta, err := c.FetchVideo(item.VideoID)
		if err != nil {
			fmt.Fprintf(logw, "  [%d] %s: SKIP (%v)\n", item.Index, item.VideoID, err)
			continue
		}
		track := pickTrack(meta.CaptionTracks, lang)
		var cues []Cue
		if track != nil {
			if cues, err = c.FetchTranscript(*track); err != nil {
				fmt.Fprintf(logw, "  [%d] %s: transcript failed (%v), writing metadata only\n",
					item.Index, meta.Title, err)
			}
		}
		doc := BuildDocument(meta, id, playlistTitle, item.Index, track, cues, time.Now())
		path, err := WriteDocument(outDir, doc)
		if err != nil {
			return err
		}
		fmt.Fprintf(logw, "  [%d] %s -> %s (%d cues)\n", item.Index, meta.Title, path, len(cues))
	}
	return nil
}

// pickTrack prefers a human track in lang, then ASR in lang, then anything.
func pickTrack(tracks []CaptionTrack, lang string) *CaptionTrack {
	var asr, any *CaptionTrack
	for i := range tracks {
		t := &tracks[i]
		if t.LanguageCode == lang && t.Kind != "asr" {
			return t
		}
		if t.LanguageCode == lang && asr == nil {
			asr = t
		}
		if any == nil {
			any = t
		}
	}
	if asr != nil {
		return asr
	}
	return any
}
