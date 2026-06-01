# Makefile for the Go Stop-Motion Video Tool

# --- Variables ---
# The name of the binary to produce
BINARY_NAME=sm

# Default build prefix is empty. It will be set for specific OSes.
BUILD_PREFIX=

# --- OS Specific Configuration ---
# Check if the OS is macOS (Darwin)
ifeq ($(shell uname -s), Darwin)
	# Attempt to find the Homebrew path for opencv4's pkg-config directory.
	PKG_PATH := $(shell brew --prefix opencv4 2>/dev/null)/lib/pkgconfig
	# If the path is found, set the build prefix to export the PKG_CONFIG_PATH.
	ifneq ("$(wildcard $(PKG_PATH))","")
		BUILD_PREFIX=PKG_CONFIG_PATH="$(PKG_PATH)"
	endif
endif


# --- Targets ---

# The default command, executed when you just run `make`.
# It ensures dependencies are installed and then builds the project.
all: deps build

# Downloads and tidies the Go module dependencies.
deps:
	@echo "--> Tidying and downloading Go module dependencies..."
	go mod tidy
	go get gocv.io/x/gocv

# Compiles the Go application.
# It automatically finds the OpenCV path for macOS/Homebrew users.
# If your OpenCV is installed elsewhere, you may need to set PKG_CONFIG_PATH manually.
# Example: PKG_CONFIG_PATH=/path/to/pkgconfig make build
build:
	@echo "--> Building the '$(BINARY_NAME)' binary..."
	# The BUILD_PREFIX variable is used here to set the environment for the go build command.
	$(BUILD_PREFIX) go build -o $(BINARY_NAME) .
	@echo "--> Build successful! Binary created: ./$(BINARY_NAME)"

# Removes the compiled binary.
clean:
	@echo "--> Cleaning up build artifacts..."
	rm -f $(BINARY_NAME)

# Provides help on how to install OpenCV on common systems.
install-help:
	@echo "--------------------------------------------------"
	@echo " This project requires OpenCV to be installed."
	@echo "--------------------------------------------------"
	@echo "On macOS (with Homebrew):"
	@echo "  brew install opencv"
	@echo ""
	@echo "On Debian/Ubuntu Linux:"
	@echo "  sudo apt-get update && sudo apt-get install libopencv-dev"
	@echo ""
	@echo "After installing, run 'make' to build the tool."
	@echo "--------------------------------------------------"

.PHONY: all deps build clean install-help

