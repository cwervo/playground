package main

import (
	"os"
	"strings"
	"testing"
)

func TestParsePlaylistJSON(t *testing.T) {
	raw, err := os.ReadFile("testdata/flat_playlist.json")
	if err != nil {
		t.Fatal(err)
	}
	pl, err := ParsePlaylistJSON(raw)
	if err != nil {
		t.Fatal(err)
	}
	if pl.Title != "Sample Playlist" || len(pl.Videos) != 2 {
		t.Fatalf("got title %q, %d videos", pl.Title, len(pl.Videos))
	}
	if pl.Videos[0].URL() != "https://www.youtube.com/watch?v=dQw4w9WgXcQ" {
		t.Fatalf("bad URL: %s", pl.Videos[0].URL())
	}
}

func TestParseGentleJSON(t *testing.T) {
	raw, err := os.ReadFile("testdata/gentle_response.json")
	if err != nil {
		t.Fatal(err)
	}
	words, err := ParseGentleJSON(raw)
	if err != nil {
		t.Fatal(err)
	}
	if len(words) != 3 {
		t.Fatalf("got %d words", len(words))
	}
	if words[0].Word != "hello" || words[0].Start != 0.34 || words[0].Case != "success" {
		t.Fatalf("bad first word: %+v", words[0])
	}
}

func TestVTTToText(t *testing.T) {
	vtt := "WEBVTT\nKind: captions\nLanguage: en\n\n00:00:00.000 --> 00:00:02.000\nhello <c>world</c>\n\n00:00:02.000 --> 00:00:04.000\nhello world\ngoodbye\n"
	got := VTTToText(vtt)
	if got != "hello world goodbye" {
		t.Fatalf("got %q", got)
	}
}

func TestEncodeTOML(t *testing.T) {
	doc := &Doc{
		Meta: &VideoMeta{
			ID: "abc123", Title: `A "quoted" title`, Uploader: "Chan",
			Duration: 12.5, Tags: []string{"go", "audio"},
			Description: "line1\nline2",
		},
		Playlist: &Playlist{ID: "PL1", Title: "Sample", Videos: make([]Video, 2)},
		Words: []AlignedWord{
			{Word: "hello", Start: 0.34, End: 0.71, Case: "success"},
			{Word: "world", Start: 0.75, End: 1.10, Case: "success", AlignedTo: "worlds"},
		},
	}
	out := EncodeTOML(doc)
	for _, want := range []string{
		`title = "A \"quoted\" title"`,
		`description = "line1\nline2"`,
		"[[transcript.words]]",
		"start = 0.340",
		`aligned_word = "worlds"`,
		`text = "hello world"`,
		"video_count = 2",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q", want)
		}
	}
}

func TestSafeFilename(t *testing.T) {
	got := SafeFilename(`What? A/B "Test": <part 1>`)
	if strings.ContainsAny(got, `/\:*?"<>|`) {
		t.Fatalf("unsafe chars remain: %q", got)
	}
}
