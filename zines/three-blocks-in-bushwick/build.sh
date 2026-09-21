#!/usr/bin/env bash
# Build the zine: A5 page PDF, A4 booklet PDF, PNG proofs.
set -euo pipefail
cd "$(dirname "$0")"
python3 make_images.py
NODE_PATH="$(npm root -g)" node render.js out/three-blocks-in-bushwick-A5-pages.pdf out/proofs
python3 impose.py out/three-blocks-in-bushwick-A5-pages.pdf out/three-blocks-in-bushwick-A4-booklet.pdf
ls -la out
