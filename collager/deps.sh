#!/bin/bash

# install_deps.sh - Dependency installer for the Collager Tcl/Tk tool on macOS.
# This script uses Homebrew to install the necessary components.

# Exit immediately if a command exits with a non-zero status. This prevents
# the script from reporting a false success if a step fails.
set -e

echo "--- Collager Dependency Installer for macOS ---"
echo "This script will check for Homebrew and use it to install:"
echo "1. A modern version of Tcl/Tk"
echo "2. FFmpeg (for video processing)"
echo "3. TkDND (for drag-and-drop)"
echo "4. Tcl-Img (for image handling)"
echo ""

# Check for Homebrew, the macOS package manager
if ! command -v brew &> /dev/null
then
    echo "Homebrew not found. Installing Homebrew first..."
    echo "You may be prompted to enter your password."
    # This is the official command from brew.sh
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for the current session. This handles both
    # Apple Silicon (/opt/homebrew) and Intel (/usr/local) installations.
    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/usr/local/bin/brew" ]; then
         eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "Homebrew is already installed. Proceeding with dependency installation."
fi

# Update Homebrew to ensure we get the latest package versions
echo ""
echo "Updating Homebrew..."
brew update

# Add the third-party tap required for the TkDND formula
# NOTE: This is another repository that provides the needed Tcl/Tk extensions.
echo ""
echo "Adding 'flight-sim/homebrew-tcl' tap to access TkDND formula..."
brew tap flight-sim/homebrew-tcl

# Install all the required packages in one command
echo ""
echo "Installing Tcl/Tk, FFmpeg, TkDND, and Tcl-Img..."
brew install tcl-tk ffmpeg tkdnd tcl-img

echo ""
echo "--- Installation Complete! ---"
echo ""
echo "To run the Collager tool, you need to use the 'wish' interpreter"
echo "that was just installed by Homebrew."
echo ""

# Dynamically find the path to the Homebrew-installed wish executable
WISH_PATH=$(brew --prefix tcl-tk)/bin/wish

if [ -f "$WISH_PATH" ]; then
    echo "You can now run the script using the following command from your terminal:"
    echo ""
    echo "  $WISH_PATH collager.tcl"
    echo ""
    echo "For convenience, you might want to create an alias in your shell profile"
    echo "(e.g., ~/.zshrc or ~/.bash_profile) by adding this line:"
    echo "  alias wish='$WISH_PATH'"
else
    echo "Could not automatically find the 'wish' executable."
    echo "Please find it in your Homebrew directory and run it with 'collager.tcl' as the argument."
fi

echo ""
echo "Enjoy creating collages!"

