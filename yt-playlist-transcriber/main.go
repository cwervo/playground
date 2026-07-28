// yt-playlist-transcriber fetches a YouTube playlist, extracts per-video
// metadata via yt-dlp, downloads audio, force-aligns the transcript with a
// Gentle server (Kaldi/C++ core), and writes one $Title.toml.txt file per
// video containing TOML metadata plus the word-aligned transcript.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

func main() {
	var (
		outDir    = flag.String("out", "out", "output directory for .toml.txt files")
		gentleURL = flag.String("gentle", "http://localhost:8765", "base URL of a running Gentle server (lowerquality/gentle)")
		audioDir  = flag.String("audio", "", "directory to cache downloaded audio (default: <out>/audio)")
		skipAlign = flag.Bool("skip-align", false, "skip Gentle alignment; emit metadata + raw captions only")
		limit     = flag.Int("limit", 0, "process at most N videos (0 = all)")
	)
	flag.Parse()

	if flag.NArg() != 1 {
		fmt.Fprintf(os.Stderr, "usage: %s [flags] <playlist-url>\n", os.Args[0])
		flag.PrintDefaults()
		os.Exit(2)
	}
	playlistURL := flag.Arg(0)

	if *audioDir == "" {
		*audioDir = filepath.Join(*outDir, "audio")
	}
	for _, d := range []string{*outDir, *audioDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			log.Fatalf("mkdir %s: %v", d, err)
		}
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pl, err := FetchPlaylist(ctx, playlistURL)
	if err != nil {
		log.Fatalf("fetch playlist: %v", err)
	}
	log.Printf("playlist %q: %d videos", pl.Title, len(pl.Videos))

	var aligner Aligner
	if !*skipAlign {
		aligner = &GentleAligner{BaseURL: *gentleURL}
		if err := aligner.(*GentleAligner).Ping(ctx); err != nil {
			log.Fatalf("gentle server not reachable at %s (%v); start one with:\n  docker run -p 8765:8765 lowerquality/gentle\nor pass -skip-align", *gentleURL, err)
		}
	}

	for i, v := range pl.Videos {
		if *limit > 0 && i >= *limit {
			break
		}
		if err := processVideo(ctx, v, pl, *outDir, *audioDir, aligner); err != nil {
			log.Printf("ERROR %s (%s): %v", v.Title, v.ID, err)
			continue
		}
		log.Printf("done %d/%d: %s", i+1, len(pl.Videos), v.Title)
	}
}

func processVideo(ctx context.Context, v Video, pl *Playlist, outDir, audioDir string, aligner Aligner) error {
	// Fetch full metadata + transcript text for this single video.
	meta, err := FetchVideoMeta(ctx, v.URL())
	if err != nil {
		return fmt.Errorf("metadata: %w", err)
	}

	var words []AlignedWord
	if aligner != nil {
		transcript, err := FetchTranscriptText(ctx, v.URL())
		if err != nil {
			return fmt.Errorf("transcript (needed for alignment): %w", err)
		}
		audioPath, err := DownloadAudio(ctx, v.URL(), audioDir, v.ID)
		if err != nil {
			return fmt.Errorf("audio: %w", err)
		}
		words, err = aligner.Align(ctx, audioPath, transcript)
		if err != nil {
			return fmt.Errorf("align: %w", err)
		}
	}

	doc := BuildDoc(meta, pl, words)
	path := filepath.Join(outDir, SafeFilename(meta.Title)+".toml.txt")
	return WriteDoc(path, doc)
}
