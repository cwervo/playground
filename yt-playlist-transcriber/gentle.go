package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"time"
)

// AlignedWord is one word with its position in the audio. Times are seconds
// as float64 — Gentle's Kaldi core emits 10 ms frame resolution, which is the
// true precision floor of MFCC-based forced alignment (there is no such thing
// as femtosecond speech alignment; 10 ms is state of the art for this method).
type AlignedWord struct {
	Word       string  `json:"word"`
	Start      float64 `json:"start"`
	End        float64 `json:"end"`
	Case       string  `json:"case"` // "success" | "not-found-in-audio"
	AlignedTo  string  `json:"alignedWord,omitempty"`
	Confidence float64 `json:"confidence,omitempty"` // mean phoneme likelihood if present
}

// Aligner produces word-level timings for a transcript against an audio file.
type Aligner interface {
	Align(ctx context.Context, audioPath, transcript string) ([]AlignedWord, error)
}

// GentleAligner talks to a running Gentle server (lowerquality/gentle).
// Gentle's alignment engine is Kaldi (C++); the server fronts it over HTTP,
// which is the practical FFI boundary — no cgo bindings needed.
type GentleAligner struct {
	BaseURL string
	Client  *http.Client
}

func (g *GentleAligner) httpClient() *http.Client {
	if g.Client != nil {
		return g.Client
	}
	return &http.Client{Timeout: 30 * time.Minute} // long videos take a while
}

// Ping checks the server is up.
func (g *GentleAligner) Ping(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, g.BaseURL+"/", nil)
	if err != nil {
		return err
	}
	resp, err := g.httpClient().Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	return nil
}

type gentleResponse struct {
	Words []struct {
		Word        string  `json:"word"`
		AlignedWord string  `json:"alignedWord"`
		Case        string  `json:"case"`
		Start       float64 `json:"start"`
		End         float64 `json:"end"`
		Phones      []struct {
			Phone    string  `json:"phone"`
			Duration float64 `json:"duration"`
		} `json:"phones"`
	} `json:"words"`
}

// Align POSTs audio + transcript to Gentle's /transcriptions endpoint.
func (g *GentleAligner) Align(ctx context.Context, audioPath, transcript string) ([]AlignedWord, error) {
	audio, err := os.Open(audioPath)
	if err != nil {
		return nil, err
	}
	defer audio.Close()

	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	fw, err := mw.CreateFormFile("audio", "audio.wav")
	if err != nil {
		return nil, err
	}
	if _, err := io.Copy(fw, audio); err != nil {
		return nil, err
	}
	if err := mw.WriteField("transcript", transcript); err != nil {
		return nil, err
	}
	mw.Close()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		g.BaseURL+"/transcriptions?async=false", &body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())

	resp, err := g.httpClient().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("gentle returned %s: %s", resp.Status, b)
	}
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return ParseGentleJSON(raw)
}

// ParseGentleJSON converts Gentle's response into AlignedWords.
func ParseGentleJSON(raw []byte) ([]AlignedWord, error) {
	var gr gentleResponse
	if err := json.Unmarshal(raw, &gr); err != nil {
		return nil, fmt.Errorf("parse gentle JSON: %w", err)
	}
	words := make([]AlignedWord, 0, len(gr.Words))
	for _, w := range gr.Words {
		words = append(words, AlignedWord{
			Word:      w.Word,
			AlignedTo: w.AlignedWord,
			Case:      w.Case,
			Start:     w.Start,
			End:       w.End,
		})
	}
	return words, nil
}
