package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/BurntSushi/toml"

	"github.com/cwervo/playground/yt2toml/align"
)

func TestExtractPlaylistID(t *testing.T) {
	for in, want := range map[string]string{
		"https://youtube.com/playlist?list=PLIV1M7mrxPqY&si=yfXuScrdKiaW5V7N": "PLIV1M7mrxPqY",
		"https://www.youtube.com/watch?v=abc&list=PLxyz":                      "PLxyz",
		"PLdirect": "PLdirect",
	} {
		got, err := ExtractPlaylistID(in)
		if err != nil || got != want {
			t.Errorf("ExtractPlaylistID(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	if _, err := ExtractPlaylistID("https://youtube.com/playlist"); err == nil {
		t.Error("expected error for URL without list=")
	}
}

func TestAlignFFI(t *testing.T) {
	start, end := align.Interval(83417, 2500)
	if start.Seconds != 83 || start.Femtos != 417_000_000_000_000 {
		t.Errorf("start = %+v", start)
	}
	if got := start.String(); got != "83.417000000000000" {
		t.Errorf("start.String() = %q", got)
	}
	if got := end.String(); got != "85.917000000000000" {
		t.Errorf("end.String() = %q", got)
	}
	// negative duration clamps, end == start
	s2, e2 := align.Interval(1000, -5)
	if s2 != e2 {
		t.Errorf("negative duration: start %+v != end %+v", s2, e2)
	}
}

func fixtureServer(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	serve := func(name string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			f, err := os.Open(filepath.Join("testdata", name))
			if err != nil {
				t.Errorf("fixture %s: %v", name, err)
				http.Error(w, "missing fixture", 500)
				return
			}
			defer f.Close()
			w.Header().Set("Content-Type", "application/json")
			io.Copy(w, f)
		}
	}
	mux.HandleFunc("/youtubei/v1/browse", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var req map[string]any
		json.Unmarshal(body, &req)
		if req["continuation"] != nil {
			serve("browse_page2.json")(w, r)
		} else {
			serve("browse_page1.json")(w, r)
		}
	})
	mux.HandleFunc("/youtubei/v1/player", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var req map[string]any
		json.Unmarshal(body, &req)
		serve("player_"+req["videoId"].(string)+".json")(w, r)
	})
	mux.HandleFunc("/api/timedtext", serve("timedtext_vid00000001.json"))
	return httptest.NewServer(mux)
}

func TestEndToEnd(t *testing.T) {
	srv := fixtureServer(t)
	defer srv.Close()
	c := &Client{HTTP: srv.Client(), BaseURL: srv.URL}

	outDir := t.TempDir()
	err := run(c, "https://youtube.com/playlist?list=PLTESTFIXTURE&si=x", outDir, "en", os.Stderr)
	if err != nil {
		t.Fatal(err)
	}

	entries, _ := os.ReadDir(outDir)
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if len(names) != 2 {
		t.Fatalf("want 2 output files, got %v", names)
	}

	data, err := os.ReadFile(filepath.Join(outDir, "Building a Tiny Compiler Part 1.toml.txt"))
	if err != nil {
		t.Fatalf("expected output file missing: %v (have %v)", err, names)
	}
	var doc Document
	if err := toml.Unmarshal(data, &doc); err != nil {
		t.Fatalf("output is not valid TOML: %v", err)
	}
	if doc.Video.ID != "vid00000001" || doc.Video.URL != "https://www.youtube.com/watch?v=vid00000001" {
		t.Errorf("video section wrong: %+v", doc.Video)
	}
	if doc.Playlist.ID != "PLTESTFIXTURE" || doc.Playlist.Index != 1 || doc.Playlist.Title != "Test Playlist" {
		t.Errorf("playlist section wrong: %+v", doc.Playlist)
	}
	if len(doc.Transcript.Cues) != 3 {
		t.Fatalf("want 3 cues, got %d", len(doc.Transcript.Cues))
	}
	c0 := doc.Transcript.Cues[0]
	if c0.Text != "hello and welcome" || c0.StartFs != "1.240000000000000" || c0.EndFs != "3.980000000000000" {
		t.Errorf("cue 0 wrong: %+v", c0)
	}
	if c0.StartSeconds != 1 || c0.StartFemtos != 240_000_000_000_000 {
		t.Errorf("cue 0 integer femtos wrong: %+v", c0)
	}
}

func TestFilenameForTitle(t *testing.T) {
	got := FilenameForTitle(`My/Weird: "Video" <Title>?`)
	if strings.ContainsAny(got, `/\:<>?"`) {
		t.Errorf("unsafe filename %q", got)
	}
	if !strings.HasSuffix(got, ".toml.txt") {
		t.Errorf("missing suffix: %q", got)
	}
}

func TestBuildDocumentMetadataOnly(t *testing.T) {
	doc := BuildDocument(&VideoMeta{ID: "x", Title: "T"}, "PL1", "P", 3, nil, nil, time.Now())
	if len(doc.Transcript.Cues) != 0 || doc.Playlist.Index != 3 {
		t.Errorf("unexpected doc: %+v", doc)
	}
}
