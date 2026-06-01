#!/bin/zsh

# run_olama_and_test.sh - Start Ollama agent and run CLI tool for testing

# Check if ollama is installed
if ! command -v ollama > /dev/null; then
  echo "Error: ollama is not installed or not in PATH. Please install Ollama first."
  exit 1
fi

# Check if Ollama server is running
if ! ollama --version | grep -q "could not connect"; then
  echo "Ollama server is running."
else
  echo "Starting Ollama agent..."
  nohup ollama serve > ollama.log 2>&1 &
  sleep 2 # Give it time to start
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
  echo "Installing npm dependencies..."
  npm install
fi

# Run CLI tool
echo "Running CLI tool: node cli.js edit ast.js"
node cli.js edit ast.js
