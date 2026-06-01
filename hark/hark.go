package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/launcher"
)

// --- STYLES ---
var (
	titleStyle     = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("63")).Padding(0, 1)
	subtleStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("242"))
	successStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("78"))
	errorStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Bold(true)
	scriptBoxStyle = lipgloss.NewStyle().Border(lipgloss.NormalBorder(), true).BorderForeground(lipgloss.Color("63")).Padding(1)
	helpStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("241")).Padding(1, 0)
)

// --- STATE MANAGEMENT ---
type state int

const (
	stateURLInput state = iota
	stateGeneratingHAR
	stateAnalyzing
	stateShowingScript
	stateExecutingScript
	stateDone
)

// --- MESSAGES (for communication between components) ---
type harGeneratedMsg struct{ harContent string }
type analysisCompleteMsg struct{ scriptContent string }
type scriptExecutedMsg struct{ output string }
type errMsg struct{ err error }

// --- MAIN MODEL ---
type model struct {
	state         state
	textInput     textinput.Model
	spinner       spinner.Model
	url           string
	harContent    string
	scriptContent string
	scriptOutput  string
	error         error
	apiKey        string
}

func initialModel() model {
	ti := textinput.New()
	ti.Placeholder = "https://example.com"
	ti.Focus()
	ti.CharLimit = 256
	ti.Width = 50

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("205"))

	apiKey := os.Getenv("GEMINI_API_KEY")

	return model{
		state:     stateURLInput,
		textInput: ti,
		spinner:   s,
		apiKey:    apiKey,
	}
}

// --- BUBBLETEA IMPLEMENTATION ---

func (m model) Init() tea.Cmd {
	return textinput.Blink
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.Type {
		case tea.KeyCtrlC, tea.KeyEsc:
			return m, tea.Quit
		case tea.KeyEnter:
			if m.state == stateURLInput {
				m.url = m.textInput.Value()
				m.state = stateGeneratingHAR
				return m, tea.Batch(m.spinner.Tick, generateHAR(m.url))
			}
		case tea.KeyRunes:
			// Handle 'y' for script execution
			if m.state == stateShowingScript && (string(msg.Runes) == "y" || string(msg.Runes) == "Y") {
				m.state = stateExecutingScript
				return m, tea.Batch(m.spinner.Tick, executeScript(m.scriptContent))
			}
		}

	// --- Handle our custom messages ---
	case harGeneratedMsg:
		m.state = stateAnalyzing
		m.harContent = msg.harContent
		return m, analyzeWithGemini(m.harContent, m.apiKey)

	case analysisCompleteMsg:
		m.state = stateShowingScript
		m.scriptContent = msg.scriptContent
		return m, nil

	case scriptExecutedMsg:
		m.state = stateDone
		m.scriptOutput = msg.output
		return m, tea.Quit

	case errMsg:
		m.error = msg.err
		return m, tea.Quit

	// --- Handle built-in messages ---
	case spinner.TickMsg:
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	}

	m.textInput, cmd = m.textInput.Update(msg)
	return m, cmd
}

func (m model) View() string {
	if m.error != nil {
		return fmt.Sprintf("\n%s\n\n%s: %v\n\n", titleStyle.Render("An error occurred!"), errorStyle.Render("ERROR"), m.error)
	}

	var b strings.Builder

	b.WriteString(titleStyle.Render("🔮 hark v1 - AI-Powered Web Performance Optimizer\n"))

	if m.apiKey == "" {
		b.WriteString(errorStyle.Render("\nError: GEMINI_API_KEY environment variable not set.\n"))
		b.WriteString(subtleStyle.Render("Please set it to use hark: export GEMINI_API_KEY='your_api_key'\n"))
		return b.String()
	}

	switch m.state {
	case stateURLInput:
		b.WriteString(subtleStyle.Render("Enter a URL to analyze and press Enter:") + "\n")
		b.WriteString(m.textInput.View())

	case stateGeneratingHAR:
		b.WriteString(fmt.Sprintf("%s Generating HAR file for %s...", m.spinner.View(), m.url))

	case stateAnalyzing:
		b.WriteString(fmt.Sprintf("%s Analyzing HAR with Gemini API...", m.spinner.View()))

	case stateShowingScript:
		b.WriteString(successStyle.Render("✔ Analysis complete! Here is the suggested optimization script:\n\n"))
		b.WriteString(scriptBoxStyle.Render(m.scriptContent))
		b.WriteString(helpStyle.Render("\nPress 'y' to execute this script, or Ctrl+C to exit."))

	case stateExecutingScript:
		b.WriteString(fmt.Sprintf("%s Executing optimization script...", m.spinner.View()))

	case stateDone:
		b.WriteString(successStyle.Render("✔ Script executed successfully!\n\n"))
		b.WriteString("--- SCRIPT OUTPUT ---\n")
		b.WriteString(m.scriptOutput)
	}

	b.WriteString(helpStyle.Render("\nPress Ctrl+C to quit at any time."))
	return b.String()
}

// --- CORE LOGIC FUNCTIONS (run as tea.Cmd) ---

// generateHAR uses go-rod to create a HAR file by capturing network traffic.
func generateHAR(url string) tea.Cmd {
	return func() tea.Msg {
		// Use a launcher to find the browser binary automatically
		path, _ := launcher.LookPath()
		if path == "" {
			// A common location on macOS, for convenience if not in PATH
			if _, err := os.Stat("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"); err == nil {
				path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
			}
		}
		if path == "" {
			return errMsg{fmt.Errorf("failed to find chrome binary. Please install Google Chrome or Chromium")}
		}

		u := launcher.New().Bin(path).MustLaunch()
		browser := rod.New().ControlURL(u).MustConnect()
		defer browser.MustClose()

		var entries []map[string]interface{}
		var mutex = &sync.Mutex{}

		router := browser.HijackRequests()
		defer router.Stop()

		router.MustAdd("*", func(ctx *rod.Hijack) {
			// Let the request continue and get the response
			ctx.MustLoadResponse()
			res := ctx.Response

			// Get response headers. res.Headers() returns an http.Header object.
			headers := res.Headers()

			// Get body size from Content-Length header.
			contentLengthStr := headers.Get("Content-Length")
			size, _ := strconv.Atoi(contentLengthStr)

			// The previous attempt to read the body caused a compiler error.
			// For this version, we'll rely on the Content-Length header, which
			// covers the vast majority of cases for static assets.
			// If a resource has no Content-Length, its size will be reported as 0.

			entry := map[string]interface{}{
				"request": map[string]interface{}{
					"url":    ctx.Request.URL().String(),
					"method": ctx.Request.Method(),
				},
				"response": map[string]interface{}{
					// The status is on the response's payload directly, under the name ResponseCode.
					"status": int(res.Payload().ResponseCode),
					"content": map[string]interface{}{
						"size":     size,
						"mimeType": headers.Get("Content-Type"),
					},
				},
			}

			mutex.Lock()
			entries = append(entries, entry)
			mutex.Unlock()
		})

		go router.Run()

		// Use MustPage which directly takes a URL and panics on error
		page := browser.MustPage(url)
		defer page.MustClose()

		// Wait for the page to be fully loaded
		page.MustWaitLoad()
		time.Sleep(3 * time.Second) // Extra wait for async resources like analytics

		harLog := map[string]interface{}{
			"log": map[string]interface{}{
				"version": "1.2",
				"creator": map[string]string{"name": "hark", "version": "1.0"},
				"entries": entries,
			},
		}

		harBytes, err := json.MarshalIndent(harLog, "", "  ")
		if err != nil {
			return errMsg{err}
		}

		return harGeneratedMsg{harContent: string(harBytes)}
	}
}

// Gemini API request structure
type GeminiRequest struct {
	Contents         []Content `json:"contents"`
	SystemInstruction Content   `json:"systemInstruction"`
}
type Content struct {
	Parts []Part `json:"parts"`
}
type Part struct {
	Text string `json:"text"`
}

// Gemini API response structure
type GeminiResponse struct {
	Candidates []struct {
		Content Content `json:"content"`
	} `json:"candidates"`
}

// analyzeWithGemini sends the HAR file to the Gemini API for analysis.
func analyzeWithGemini(harContent, apiKey string) tea.Cmd {
	return func() tea.Msg {
		systemPrompt := `You are an expert web performance analyst. A user will provide a HAR file.
		Your task is to analyze it, identify the top 3-5 most impactful optimization opportunities, and generate a bash script to fix them.
		The script should be the ONLY thing you output. It should be well-commented, explaining what each command does.
		Focus on actionable advice: image compression (suggesting webp), caching headers (for Cloudflare/Netlify via _headers), and asset minification.
		Do NOT include placeholders. Assume common tools like 'curl' and 'cwebp' are available. The output must be a valid bash script and nothing else.`

		userPrompt := "Analyze this HAR file and generate the optimization script:\n\n" + harContent

		reqPayload := GeminiRequest{
			Contents: []Content{
				{Parts: []Part{{Text: userPrompt}}},
			},
			SystemInstruction: Content{
				Parts: []Part{{Text: systemPrompt}},
			},
		}

		payloadBytes, err := json.Marshal(reqPayload)
		if err != nil {
			return errMsg{err}
		}

		apiURL := "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent?key=" + apiKey
		req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(payloadBytes))
		if err != nil {
			return errMsg{err}
		}
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{Timeout: 60 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			return errMsg{err}
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return errMsg{err}
		}

		if resp.StatusCode != http.StatusOK {
			return errMsg{fmt.Errorf("API request failed with status %d: %s", resp.StatusCode, string(body))}
		}

		var geminiResp GeminiResponse
		if err := json.Unmarshal(body, &geminiResp); err != nil {
			return errMsg{err}
		}

		if len(geminiResp.Candidates) > 0 && len(geminiResp.Candidates[0].Content.Parts) > 0 {
			script := geminiResp.Candidates[0].Content.Parts[0].Text
			// Clean up the script from markdown code fences if they exist
			script = strings.TrimPrefix(script, "```bash\n")
			script = strings.TrimSuffix(script, "```")
			return analysisCompleteMsg{scriptContent: strings.TrimSpace(script)}
		}

		return errMsg{fmt.Errorf("no content received from Gemini API")}
	}
}

// executeScript runs the generated bash script.
func executeScript(scriptContent string) tea.Cmd {
	return func() tea.Msg {
		// Create a temporary script file
		file, err := os.CreateTemp("", "hark-script-*.sh")
		if err != nil {
			return errMsg{err}
		}
		defer os.Remove(file.Name()) // Clean up the file

		_, err = file.WriteString(scriptContent)
		if err != nil {
			return errMsg{err}
		}
		file.Close() // Close the file so it can be executed

		// Make the script executable
		if err := os.Chmod(file.Name(), 0755); err != nil {
			return errMsg{err}
		}

		// Execute the script
		cmd := exec.Command("bash", file.Name())
		var out bytes.Buffer
		cmd.Stdout = &out
		cmd.Stderr = &out
		err = cmd.Run()
		if err != nil {
			// Include output in the error message for context
			return errMsg{fmt.Errorf("script execution failed: %v\nOutput:\n%s", err, out.String())}
		}

		return scriptExecutedMsg{output: out.String()}
	}
}

// --- MAIN FUNCTION ---
func main() {
	p := tea.NewProgram(initialModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		log.Fatalf("Alas, there's been an error: %v", err)
	}
}
