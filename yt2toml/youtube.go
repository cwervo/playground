package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

// Client talks to YouTube's InnerTube API (the JSON API the web player uses;
// no API key required). BaseURL is swappable so tests can run against fixtures.
type Client struct {
	HTTP    *http.Client
	BaseURL string // e.g. "https://www.youtube.com"
}

func NewClient() *Client {
	return &Client{HTTP: http.DefaultClient, BaseURL: "https://www.youtube.com"}
}

var innertubeContext = map[string]any{
	"client": map[string]any{
		"clientName":    "WEB",
		"clientVersion": "2.20240701.00.00",
		"hl":            "en",
	},
}

// PlaylistItem is one entry of a playlist listing.
type PlaylistItem struct {
	VideoID string
	Title   string
	Index   int
}

// VideoMeta is the per-video metadata pulled from the player response.
type VideoMeta struct {
	ID            string
	Title         string
	Author        string
	ChannelID     string
	LengthSeconds int64
	ViewCount     int64
	Description   string
	Keywords      []string
	CaptionTracks []CaptionTrack
}

type CaptionTrack struct {
	BaseURL      string
	LanguageCode string
	Name         string
	Kind         string // "asr" for auto-generated
}

// Cue is one transcript segment with millisecond source timing.
type Cue struct {
	Text    string
	StartMs int64
	DurMs   int64
}

var playlistIDRe = regexp.MustCompile(`^[A-Za-z0-9_-]{2,}$`)

// ExtractPlaylistID pulls the list= parameter out of a playlist URL,
// accepting a bare ID too.
func ExtractPlaylistID(raw string) (string, error) {
	if playlistIDRe.MatchString(raw) && !strings.Contains(raw, "/") {
		return raw, nil
	}
	u, err := url.Parse(raw)
	if err != nil {
		return "", fmt.Errorf("parse url: %w", err)
	}
	id := u.Query().Get("list")
	if id == "" {
		return "", fmt.Errorf("no list= parameter in %q", raw)
	}
	return id, nil
}

func (c *Client) post(path string, body map[string]any) (map[string]any, error) {
	buf, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("POST", c.BaseURL+path, bytes.NewReader(buf))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("%s: HTTP %d", path, resp.StatusCode)
	}
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out, nil
}

// FetchPlaylist lists all videos in a playlist, following continuations.
func (c *Client) FetchPlaylist(id string) ([]PlaylistItem, string, error) {
	doc, err := c.post("/youtubei/v1/browse", map[string]any{
		"context": innertubeContext, "browseId": "VL" + id,
	})
	if err != nil {
		return nil, "", err
	}
	title, _ := dig(doc, "metadata", "playlistMetadataRenderer", "title").(string)

	var items []PlaylistItem
	for {
		var next string
		walk(doc, func(key string, node map[string]any) {
			switch key {
			case "playlistVideoRenderer":
				vid, _ := node["videoId"].(string)
				items = append(items, PlaylistItem{
					VideoID: vid,
					Title:   runsText(node["title"]),
					Index:   len(items) + 1,
				})
			case "continuationCommand":
				if t, ok := node["token"].(string); ok && next == "" {
					next = t
				}
			}
		})
		if next == "" {
			break
		}
		doc, err = c.post("/youtubei/v1/browse", map[string]any{
			"context": innertubeContext, "continuation": next,
		})
		if err != nil {
			return items, title, err
		}
	}
	return items, title, nil
}

// FetchVideo fetches the player response for one video.
func (c *Client) FetchVideo(videoID string) (*VideoMeta, error) {
	doc, err := c.post("/youtubei/v1/player", map[string]any{
		"context": innertubeContext, "videoId": videoID,
	})
	if err != nil {
		return nil, err
	}
	vd, _ := dig(doc, "videoDetails").(map[string]any)
	if vd == nil {
		return nil, fmt.Errorf("video %s: no videoDetails in player response", videoID)
	}
	m := &VideoMeta{
		ID:          str(vd["videoId"]),
		Title:       str(vd["title"]),
		Author:      str(vd["author"]),
		ChannelID:   str(vd["channelId"]),
		Description: str(vd["shortDescription"]),
	}
	m.LengthSeconds, _ = strconv.ParseInt(str(vd["lengthSeconds"]), 10, 64)
	m.ViewCount, _ = strconv.ParseInt(str(vd["viewCount"]), 10, 64)
	if kw, ok := vd["keywords"].([]any); ok {
		for _, k := range kw {
			m.Keywords = append(m.Keywords, str(k))
		}
	}
	if tracks, ok := dig(doc, "captions", "playerCaptionsTracklistRenderer", "captionTracks").([]any); ok {
		for _, t := range tracks {
			tm, _ := t.(map[string]any)
			if tm == nil {
				continue
			}
			m.CaptionTracks = append(m.CaptionTracks, CaptionTrack{
				BaseURL:      str(tm["baseUrl"]),
				LanguageCode: str(tm["languageCode"]),
				Kind:         str(tm["kind"]),
				Name:         runsText(tm["name"]),
			})
		}
	}
	return m, nil
}

// FetchTranscript downloads a caption track in json3 format and flattens it
// into cues. Relative track URLs are resolved against the client base URL.
func (c *Client) FetchTranscript(track CaptionTrack) ([]Cue, error) {
	u := track.BaseURL
	if strings.HasPrefix(u, "/") {
		u = c.BaseURL + u
	}
	if !strings.Contains(u, "fmt=") {
		sep := "?"
		if strings.Contains(u, "?") {
			sep = "&"
		}
		u += sep + "fmt=json3"
	}
	resp, err := c.HTTP.Get(u)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("timedtext: HTTP %d", resp.StatusCode)
	}
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return parseJSON3(raw)
}

func parseJSON3(raw []byte) ([]Cue, error) {
	var doc struct {
		Events []struct {
			TStartMs    int64 `json:"tStartMs"`
			DDurationMs int64 `json:"dDurationMs"`
			Segs        []struct {
				UTF8 string `json:"utf8"`
			} `json:"segs"`
		} `json:"events"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, fmt.Errorf("parse json3 transcript: %w", err)
	}
	var cues []Cue
	for _, ev := range doc.Events {
		var b strings.Builder
		for _, s := range ev.Segs {
			b.WriteString(s.UTF8)
		}
		text := strings.TrimSpace(strings.ReplaceAll(b.String(), "\n", " "))
		if text == "" {
			continue
		}
		cues = append(cues, Cue{Text: text, StartMs: ev.TStartMs, DurMs: ev.DDurationMs})
	}
	return cues, nil
}

// --- small generic-JSON helpers ---

func str(v any) string { s, _ := v.(string); return s }

func dig(m map[string]any, path ...string) any {
	var cur any = m
	for _, p := range path {
		mm, ok := cur.(map[string]any)
		if !ok {
			return nil
		}
		cur = mm[p]
	}
	return cur
}

// runsText flattens YouTube's {"runs":[{"text":...}]} / {"simpleText":...} shapes.
func runsText(v any) string {
	m, ok := v.(map[string]any)
	if !ok {
		return ""
	}
	if s, ok := m["simpleText"].(string); ok {
		return s
	}
	runs, _ := m["runs"].([]any)
	var b strings.Builder
	for _, r := range runs {
		if rm, ok := r.(map[string]any); ok {
			b.WriteString(str(rm["text"]))
		}
	}
	return b.String()
}

// walk visits every object in a decoded JSON tree, reporting each key whose
// value is an object.
func walk(v any, visit func(key string, node map[string]any)) {
	switch t := v.(type) {
	case map[string]any:
		for k, child := range t {
			if cm, ok := child.(map[string]any); ok {
				visit(k, cm)
			}
			walk(child, visit)
		}
	case []any:
		for _, child := range t {
			walk(child, visit)
		}
	}
}
