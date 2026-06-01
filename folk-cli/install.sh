#!/bin/sh

# Folk Computer v1 Installer
# This script automates the installation of the Folk computer environment on
# macOS and Debian-based Linux systems.

# --- Configuration ---
# The Git repository to clone.
FOLK_REPO="https://github.com/FolkComputer/folk.git"
# The directory where Folk will be installed.
INSTALL_DIR="$HOME/.folk"
# The location for the CLI command.
CMD_PATH="/usr/local/bin/folk"


# --- Helper Functions ---

# Prints a message with a decorative header.
print_header() {
    printf "\n--- %s ---\n" "$(echo "$1" | tr '[:lower:]' '[:upper:]')"
}

# Checks if a command exists.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Asks the user for a yes/no confirmation.
ask_confirm() {
    while true; do
        printf "%s [y/n] " "$1"
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# --- Main Script Logic ---

print_header "Welcome to the Folk Installer!"
echo "This script will download and set up the Folk computer on your system."

# 1. Determine OS and define dependencies.
OS=""
PKG_MANAGER=""

if [ "$(uname)" = "Darwin" ]; then
    OS="macOS"
    PKG_MANAGER="brew"
    # Replaced glslc with glslang for Homebrew compatibility
    DEPS="git tcl-tk vulkan-tools pkg-config meson glslang ghostscript"
elif [ -f /etc/debian_version ]; then
    OS="debian"
    PKG_MANAGER="apt-get"
    # Added avahi-daemon for .local hostname resolution
    DEPS="git tcl-thread tcl8.6-dev libjpeg-dev libpng-dev libdrm-dev pkg-config v4l-utils mesa-vulkan-drivers vulkan-tools libvulkan-dev libvulkan1 meson libgbm-dev glslc vulkan-validationlayers ghostscript avahi-daemon"
else
    echo "ERROR: Your operating system is not supported by this installer." >&2
    echo "Please follow the manual installation instructions." >&2
    exit 1
fi

# 2. Check for the package manager and install dependencies.
print_header "Checking System Dependencies"

if ! command_exists "$PKG_MANAGER"; then
    echo "ERROR: Package manager '$PKG_MANAGER' not found." >&2
    if [ "$OS" = "macOS" ]; then
        echo "Please install Homebrew from https://brew.sh and try again." >&2
    fi
    exit 1
fi

echo "The following packages will be installed using '$PKG_MANAGER':"
echo "  $DEPS"

if ask_confirm "Proceed with installation?"; then
    # Elevate to sudo only for package management, and only when needed.
    if [ "$OS" = "debian" ]; then
        echo "Administrator privileges are required to install packages."
        sudo apt-get update
        sudo apt-get install -y $DEPS
    elif [ "$OS" = "macOS" ]; then
        # Homebrew should NOT be run with sudo.
        brew install $DEPS
    fi
    echo "✅ Dependencies installed successfully."
else
    echo "Aborting installation."
    exit 1
fi

# 3. Clone Folk and compile components (as the current user).
print_header "Downloading and Installing Folk"

if [ -d "$INSTALL_DIR" ]; then
    echo "Folk directory already exists at '$INSTALL_DIR'. Pulling latest changes..."
    (cd "$INSTALL_DIR" && git pull)
else
    echo "Cloning Folk into '$INSTALL_DIR'..."
    git clone "$FOLK_REPO" "$INSTALL_DIR"
fi

# CRITICAL FIX: Initialize and update git submodules
echo "Initializing and updating submodules (apriltag, etc.)..."
(cd "$INSTALL_DIR" && git submodule update --init --recursive)


echo "Compiling required components..."
if [ -d "$INSTALL_DIR/vendor/apriltag" ]; then
    (cd "$INSTALL_DIR/vendor/apriltag" && make libapriltag.so libapriltag.a)
    echo "✅ Folk downloaded and compiled successfully."
else
    echo "❌ ERROR: Could not find the 'vendor/apriltag' directory to compile." >&2
    echo "   This might be a submodule issue." >&2
    exit 1
fi


# 4. Configure Hostname (as the current user).
print_header "Configuring Hostname"
printf "What should this folk's name be? (e.g. 'tabletop', 'dev')\n"
printf "This will be used to create the hostname 'folk-yourname.local'.\n> "
read -r folk_name
FOLK_HOSTNAME="folk-${folk_name}"
echo "FOLK_HOSTNAME=$FOLK_HOSTNAME" > "$INSTALL_DIR/config"
echo "✅ Hostname set to '$FOLK_HOSTNAME'."


# 5. Create the 'folk' CLI command (using sudo for this step only).
print_header "Creating 'folk' command"
echo "Administrator privileges are required to create the command in $CMD_PATH."

# Use a 'here document' with sudo to write the script content.
sudo sh -c "cat > '$CMD_PATH'" << EOF
#!/bin/sh
# Wrapper script for managing the Folk application

FOLK_DIR="\$HOME/.folk"
CONFIG_FILE="\$FOLK_DIR/config"
LOG_FILE="/tmp/folk.log"

# Ensure the directory exists
if [ ! -d "\$FOLK_DIR" ]; then
    echo "Folk installation not found at \$FOLK_DIR"
    exit 1
fi

# Load configuration
if [ -f "\$CONFIG_FILE" ]; then
    . "\$CONFIG_FILE"
fi

get_pid() {
    pgrep -f "tclsh8.6 main.tcl \$FOLK_HOSTNAME"
}

case "\$1" in
  start)
    if [ -z "\$FOLK_HOSTNAME" ]; then
        echo "Hostname not configured. Please re-run the installer."
        exit 1
    fi
    if [ -n "\$(get_pid)" ]; then
        echo "Folk is already running."
        exit 0
    fi

    echo "Starting Folk with hostname '\$FOLK_HOSTNAME'..."
    cd "\$FOLK_DIR" || exit
    
    # Run in the background
    nohup tclsh8.6 main.tcl "\$FOLK_HOSTNAME" > "\$LOG_FILE" 2>&1 &
    
    # Verify that the process started successfully
    sleep 1
    PID=\$(get_pid)
    if [ -n "\$PID" ]; then
        echo "✅ Folk is running with PID: \$PID"
        echo "   View logs at: \$LOG_FILE"
        echo "   Access the web UI at http://localhost:4273"
        echo "   (or http://\$FOLK_HOSTNAME.local:4273 from another device on your network)"
    else
        echo "❌ Folk failed to start. Check logs for errors:"
        echo "   cat \$LOG_FILE"
    fi
    ;;
  stop)
    echo "Stopping Folk..."
    PID=\$(get_pid)
    if [ -n "\$PID" ]; then
        kill "\$PID"
        echo "Folk stopped."
    else
        echo "Folk does not appear to be running."
    fi
    ;;
  status)
    PID=\$(get_pid)
    if [ -n "\$PID" ]; then
        echo "✅ Folk is running with PID: \$PID (Hostname: \${FOLK_HOSTNAME})"
    else
        echo "❌ Folk is not running."
    fi
    ;;
  logs)
    echo "Tailing logs... (Press Ctrl+C to exit)"
    tail -f "\$LOG_FILE"
    ;;
  top)
    trap 'clear; printf "Exiting top view.\\n"; exit 0' INT
    while true; do
        clear
        echo "--- Folk Monitor (Press Ctrl+C to exit) ---"
        echo
        "\$0" status
        echo
        echo "--- Last 15 Lines of Log (\$LOG_FILE) ---"
        tail -n 15 "\$LOG_FILE"
        sleep 2
    done
    ;;
  update)
    echo "Updating Folk from git..."
    (cd "\$FOLK_DIR" && git pull && git submodule update --init --recursive)
    echo "Re-compiling components..."
    (cd "\$FOLK_DIR/vendor/apriltag" && make libapriltag.so libapriltag.a)
    echo "Update complete."
    ;;
  uninstall)
    echo "This will stop Folk and remove all related files."
    printf "Are you sure? (y/n) "
    read -r confirmation
    if [ "\$confirmation" = "y" ]; then
        "\$0" stop > /dev/null 2>&1
        echo "Removing files..."
        rm -rf "\$FOLK_DIR"
        sudo rm -f $CMD_PATH
        echo "Folk has been uninstalled."
    else
        echo "Uninstall cancelled."
    fi
    ;;
  *)
    echo "Usage: folk {start|stop|status|logs|top|update|uninstall}"
    exit 1
    ;;
esac
EOF

# Make the script executable
sudo chmod +x "$CMD_PATH"
echo "✅ Command created at '$CMD_PATH'."

# --- Final Message ---
print_header "🚀 Installation Complete!"
echo "You can now manage your Folk instance using the 'folk' command:"
echo "  folk start      - Start the Folk application"
echo "  folk stop       - Stop the Folk application"
echo "  folk status     - Check if Folk is running"
echo "  folk logs       - View live log output"
echo "  folk top        - Monitor status and logs"
echo "  folk update     - Update to the latest version"
echo "  folk uninstall  - Remove Folk from your system"
echo
echo "Run 'folk start' to begin!"

