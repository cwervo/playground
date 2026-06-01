package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)


// --- Gemini API Structs (Unchanged) ---
const GEMINI_API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent"
type GeminiRequest struct { Contents []Content; SafetySettings []SafetySetting }
type Content struct{ Parts []Part }
type Part struct{ Text string }
type GeminiResponse struct { Candidates []struct { Content struct { Parts []struct { Text string } } } }
type SafetySetting struct { Category, Threshold string }

// --- API Call Helper ---
// Centralizes the logic for making the API call
func callGemini(prompt, apiKey string) (string, error) {
	requestBody := GeminiRequest{
		Contents:       []Content{{Parts: []Part{{Text: prompt}}}},
		SafetySettings: []SafetySetting{{Category: "HARM_CATEGORY_HARASSMENT", Threshold: "BLOCK_NONE"}},
	}
	jsonBody, err := json.Marshal(requestBody)
	if err != nil { return "", fmt.Errorf("error creating request body: %w", err) }

	url := fmt.Sprintf("%s?key=%s", GEMINI_API_ENDPOINT, apiKey)
	req, err := http.NewRequestWithContext(context.Background(), "POST", url, bytes.NewBuffer(jsonBody))
	if err != nil { return "", fmt.Errorf("error creating HTTP request: %w", err) }
	
	req.Header.Set("Content-Type", "application/json")
	
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil { return "", fmt.Errorf("error sending request to API: %w", err) }
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("API Error: status code %d, response: %s", resp.StatusCode, string(bodyBytes))
	}

	var geminiResp GeminiResponse
	if err := json.NewDecoder(resp.Body).Decode(&geminiResp); err != nil {
		return "", fmt.Errorf("error decoding API response: %w", err)
	}

	if len(geminiResp.Candidates) > 0 && len(geminiResp.Candidates[0].Content.Parts) > 0 {
		return geminiResp.Candidates[0].Content.Parts[0].Text, nil
	}
	
	return "No content received in response.", nil
}


// --- New Static Help Text ---
func showHelpText() {
	fmt.Println(`
gc - A command-line interface for Google's Gemini.

USAGE:
  gc [flags] [prompt...]
  <command> | gc [flags] [prompt...]

BEHAVIOR:
  - With a prompt         : Executes the prompt immediately.
  - With piped data (STDIN): Uses the piped data as the primary input.
  - With -i flag          : Enters an interactive chat session.

FLAGS:
  -h, -H, --help          : Show this help message.
  -i                      : Start an interactive REPL session.

EXAMPLES:
  # Prompt via arguments
  gc "Write a Go function that sorts a list of strings"

  # Prompt via STDIN
  cat main.go | gc "Refactor this code for clarity"

  # Interactive chat
  gc -i
	`)
}


// --- New Interactive Session (for -i flag) ---
func startInteractiveSession(apiKey string) {
	fmt.Println("🚀 Starting interactive Gemini session... (type 'exit' or 'quit' to end)")
	scanner := bufio.NewScanner(os.Stdin)
	
	for {
		fmt.Print("> ")
		if !scanner.Scan() {
			break // Exit on EOF (Ctrl+D)
		}
		
		input := scanner.Text()
		if input == "exit" || input == "quit" {
			break
		}
		
		if input == "" {
			continue
		}

		fmt.Println("...") // Indicate that we're waiting for the API
		response, err := callGemini(input, apiKey)
		if err != nil {
			log.Printf("API Error: %v", err)
			continue
		}
		fmt.Println(response)
	}
	fmt.Println("Exiting session.")
}

// --- REFACTORED Main Function ---
func main() {
	// Define flags
	helpFlagH := flag.Bool("H", false, "Show help")
	helpFlagh := flag.Bool("h", false, "Show help")
	helpFlagHelp := flag.Bool("help", false, "Show help")
	interactiveFlag := flag.Bool("i", false, "Start an interactive session")
	
	flag.Parse()

	// 1. Handle Help Flag
	if *helpFlagH || *helpFlagh || *helpFlagHelp {
		showHelpText()
		return
	}
	
	apiKey := os.Getenv("GOOGLE_API_KEY")
	if apiKey == "" {
		log.Fatal("Error: The GOOGLE_API_KEY environment variable is not set.")
	}
	
	// 2. Handle Interactive Flag
	if *interactiveFlag {
		startInteractiveSession(apiKey)
		return
	}

	// 3. Handle STDIN and Argument-based prompts
	stat, _ := os.Stdin.Stat()
	var pipedInput string
	if (stat.Mode() & os.ModeCharDevice) == 0 {
		pipedBytes, err := io.ReadAll(os.Stdin)
		if err != nil { log.Fatalf("Error reading from stdin: %v", err) }
		pipedInput = string(pipedBytes)
	}

	cliPrompt := strings.Join(flag.Args(), " ")

	if cliPrompt == "" && pipedInput == "" {
		// This now correctly exits with a helpful message.
		fmt.Fprintln(os.Stderr, "No prompt provided. Waiting for STDIN or use -i for interactive mode.")
		os.Exit(1)
	}

	fullPrompt := ""
	if pipedInput != "" {
		fullPrompt = fmt.Sprintf("--- Piped Input ---\n%s\n--- User Prompt ---\n%s", pipedInput, cliPrompt)
	} else {
		fullPrompt = cliPrompt
	}

	response, err := callGemini(fullPrompt, apiKey)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(response)
}
