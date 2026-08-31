#!/bin/bash
# Fallback shader build for toolchains where SwiftPM does not compile .metal sources.
# Produces .build/default.metallib, which MetalContext probes for at runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun -sdk macosx metal -c Sources/Sistine/GPU/Shaders.metal -o .build/Shaders.air
xcrun -sdk macosx metallib .build/Shaders.air -o .build/default.metallib
echo "wrote .build/default.metallib"
