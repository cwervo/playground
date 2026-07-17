#!/bin/bash
# Build and release the lilguys onto your desktop.
set -euo pipefail
cd "$(dirname "$0")"

# Symlink the project onto the Desktop, as ~/Desktop/playground/lilguys.
mkdir -p "$HOME/Desktop/playground"
ln -sfn "$(pwd)" "$HOME/Desktop/playground/lilguys"

swiftc -O Lilguys.swift -o lilguysd
exec ./lilguysd "${1:-lilguys.lg}"
