package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// Playlist is the parsed result of a yt-dlp --flat-playlist dump.
type Playlist struct {
	ID       string
	Title    string
	Uploader string
	URL      string
	Videos   []Video
}

// Video is one flat playlist entry.
type Video struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

func (v Video) URL() string { return "https://www.youtube.com/watch?v=" + v.ID }

// VideoMeta is the full single-video metadata we keep.
type VideoMeta struct {
	ID           string   `json:"id"`
	Title        string   `json:"title"`
	Description  string   `json:"description"`
	Uploader     string   `json:"uploader"`
	ChannelID    string   `json:"channel_id"`
	UploadDate   string   `json:"upload_date"`
	Duration     float64  `json:"duration"`
	ViewCount    int64    `json:"view_count"`
	LikeCount    int64    `json:"like_count"`
	Tags         []string `json:"tags"`
	Categories   []string `json:"categories"`
	WebpageURL   string   `json:"webpage_url"`
	ChannelURL   string   `json:"channel_url"`
	Thumbnail    string   `json:"thumbnail"`
	Availability string   `json:"availability"`
}

type flatPlaylist struct {
	ID       string  `json:"id"`
	Title    string  `json:"title"`
	Uploader string  `json:"uploader"`
	URL      string  `json:"webpage_url"`
	Entries  []Video `json:"entries"`
}

func runYtdlp(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "yt-dlp", args...)
	var out, errb bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errb
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("yt-dlp %v: %w: %s", args, err, strings.TrimSpace(errb.String()))
	}
	return out.Bytes(), nil
}

// FetchPlaylist lists a playlist's entries without resolving each video.
func FetchPlaylist(ctx context.Context, url string) (*Playlist, error) {
	raw, err := runYtdlp(ctx, "--flat-playlist", "-J", url)
	if err != nil {
		return nil, err
	}
	return ParsePlaylistJSON(raw)
}

// ParsePlaylistJSON parses yt-dlp --flat-playlist -J output.
func ParsePlaylistJSON(raw []byte) (*Playlist, error) {
	var fp flatPlaylist
	if err := json.Unmarshal(raw, &fp); err != nil {
		return nil, fmt.Errorf("parse playlist JSON: %w", err)
	}
	videos := make([]Video, 0, len(fp.Entries))
	for _, e := range fp.Entries {
		if e.ID != "" {
			videos = append(videos, e)
		}
	}
	return &Playlist{ID: fp.ID, Title: fp.Title, Uploader: fp.Uploader, URL: fp.URL, Videos: videos}, nil
}

// FetchVideoMeta pulls full metadata for a single video.
func FetchVideoMeta(ctx context.Context, url string) (*VideoMeta, error) {
	raw, err := runYtdlp(ctx, "-J", "--no-download", url)
	if err != nil {
		return nil, err
	}
	var m VideoMeta
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, fmt.Errorf("parse video JSON: %w", err)
	}
	return &m, nil
}

// FetchTranscriptText downloads the video's captions (manual preferred,
// auto-generated fallback) and returns them as plain text for alignment.
func FetchTranscriptText(ctx context.Context, url string) (string, error) {
	dir, err := os.MkdirTemp("", "subs-*")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(dir)

	_, err = runYtdlp(ctx,
		"--skip-download",
		"--write-subs", "--write-auto-subs",
		"--sub-langs", "en.*,en",
		"--sub-format", "vtt",
		"-o", filepath.Join(dir, "%(id)s"),
		url)
	if err != nil {
		return "", err
	}
	matches, _ := filepath.Glob(filepath.Join(dir, "*.vtt"))
	if len(matches) == 0 {
		return "", fmt.Errorf("no English captions available")
	}
	raw, err := os.ReadFile(matches[0])
	if err != nil {
		return "", err
	}
	return VTTToText(string(raw)), nil
}

var (
	vttTimeRe = regexp.MustCompile(`^\s*(\d{2}:)?\d{2}:\d{2}[.,]\d{3}\s+-->`)
	vttTagRe  = regexp.MustCompile(`<[^>]*>`)
)

// VTTToText strips WebVTT structure/tags and de-duplicates the rolling
// repeated lines that YouTube auto-captions produce.
func VTTToText(vtt string) string {
	var out []string
	last := ""
	for _, line := range strings.Split(vtt, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || line == "WEBVTT" ||
			strings.HasPrefix(line, "Kind:") || strings.HasPrefix(line, "Language:") ||
			strings.HasPrefix(line, "NOTE") || vttTimeRe.MatchString(line) {
			continue
		}
		line = strings.TrimSpace(vttTagRe.ReplaceAllString(line, ""))
		if line == "" || line == last {
			continue
		}
		out = append(out, line)
		last = line
	}
	return strings.Join(out, " ")
}

// DownloadAudio fetches the best audio stream as 16 kHz mono WAV (what
// Gentle/Kaldi wants) into dir, returning the file path. Cached by video ID.
func DownloadAudio(ctx context.Context, url, dir, id string) (string, error) {
	wav := filepath.Join(dir, id+".wav")
	if _, err := os.Stat(wav); err == nil {
		return wav, nil
	}
	_, err := runYtdlp(ctx,
		"-f", "bestaudio",
		"--extract-audio", "--audio-format", "wav",
		"--postprocessor-args", "ffmpeg:-ar 16000 -ac 1",
		"-o", filepath.Join(dir, id+".%(ext)s"),
		url)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(wav); err != nil {
		return "", fmt.Errorf("expected %s after download: %w", wav, err)
	}
	return wav, nil
}
