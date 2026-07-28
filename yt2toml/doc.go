package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/BurntSushi/toml"

	"github.com/cwervo/playground/yt2toml/align"
)

// Document is the on-disk shape of one $Title.toml.txt file.
type Document struct {
	Video      VideoSection      `toml:"video"`
	Playlist   PlaylistSection   `toml:"playlist"`
	Transcript TranscriptSection `toml:"transcript"`
}

type VideoSection struct {
	ID            string   `toml:"id"`
	URL           string   `toml:"url"`
	Title         string   `toml:"title"`
	Channel       string   `toml:"channel"`
	ChannelID     string   `toml:"channel_id"`
	LengthSeconds int64    `toml:"length_seconds"`
	ViewCount     int64    `toml:"view_count"`
	Keywords      []string `toml:"keywords,omitempty"`
	Description   string   `toml:"description,multiline,omitempty"`
	FetchedAt     string   `toml:"fetched_at"`
}

type PlaylistSection struct {
	ID    string `toml:"id"`
	URL   string `toml:"url"`
	Title string `toml:"title,omitempty"`
	Index int    `toml:"index"`
}

type TranscriptSection struct {
	Language  string    `toml:"language,omitempty"`
	Kind      string    `toml:"kind,omitempty"` // "asr" = auto-generated
	Source    string    `toml:"source"`
	Precision string    `toml:"precision_note"`
	Cues      []CueToml `toml:"cue,omitempty"`
}

// CueToml carries each cue's source millisecond timing plus the C++-aligned
// femtosecond fixed-point encoding (decimal string and exact integer pair).
type CueToml struct {
	Text         string `toml:"text"`
	StartMs      int64  `toml:"start_ms"`
	EndMs        int64  `toml:"end_ms"`
	StartFs      string `toml:"start_fs"`
	EndFs        string `toml:"end_fs"`
	StartSeconds int64  `toml:"start_seconds"`
	StartFemtos  int64  `toml:"start_femtoseconds"`
	EndSeconds   int64  `toml:"end_seconds"`
	EndFemtos    int64  `toml:"end_femtoseconds"`
}

const precisionNote = "timestamps encoded at femtosecond fixed-point resolution via the Go/C++ FFI aligner; " +
	"source measurement resolution is milliseconds (YouTube timedtext)"

// BuildDocument assembles the TOML document for one video.
func BuildDocument(meta *VideoMeta, playlistID, playlistTitle string, index int,
	track *CaptionTrack, cues []Cue, now time.Time) Document {

	doc := Document{
		Video: VideoSection{
			ID:            meta.ID,
			URL:           "https://www.youtube.com/watch?v=" + meta.ID,
			Title:         meta.Title,
			Channel:       meta.Author,
			ChannelID:     meta.ChannelID,
			LengthSeconds: meta.LengthSeconds,
			ViewCount:     meta.ViewCount,
			Keywords:      meta.Keywords,
			Description:   meta.Description,
			FetchedAt:     now.UTC().Format(time.RFC3339),
		},
		Playlist: PlaylistSection{
			ID:    playlistID,
			URL:   "https://www.youtube.com/playlist?list=" + playlistID,
			Title: playlistTitle,
			Index: index,
		},
		Transcript: TranscriptSection{
			Source:    "youtube-timedtext-json3",
			Precision: precisionNote,
		},
	}
	if track != nil {
		doc.Transcript.Language = track.LanguageCode
		doc.Transcript.Kind = track.Kind
	}
	for _, c := range cues {
		start, end := align.Interval(c.StartMs, c.DurMs)
		doc.Transcript.Cues = append(doc.Transcript.Cues, CueToml{
			Text:         c.Text,
			StartMs:      c.StartMs,
			EndMs:        c.StartMs + max64(c.DurMs, 0),
			StartFs:      start.String(),
			EndFs:        end.String(),
			StartSeconds: start.Seconds,
			StartFemtos:  start.Femtos,
			EndSeconds:   end.Seconds,
			EndFemtos:    end.Femtos,
		})
	}
	return doc
}

func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}

var unsafeFilename = regexp.MustCompile(`[^\p{L}\p{N} ._-]+`)

// FilenameForTitle sanitizes a video title into "$Title.toml.txt".
func FilenameForTitle(title string) string {
	name := unsafeFilename.ReplaceAllString(title, "_")
	name = strings.Trim(strings.Join(strings.Fields(name), " "), " ._")
	if name == "" {
		name = "untitled"
	}
	if len(name) > 150 {
		name = name[:150]
	}
	return name + ".toml.txt"
}

// WriteDocument encodes the document as TOML into outDir.
func WriteDocument(outDir string, doc Document) (string, error) {
	path := filepath.Join(outDir, FilenameForTitle(doc.Video.Title))
	f, err := os.Create(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	fmt.Fprintf(f, "# yt2toml — %s\n# generated %s\n\n", doc.Video.Title, doc.Video.FetchedAt)
	if err := toml.NewEncoder(f).Encode(doc); err != nil {
		return "", err
	}
	return path, nil
}
