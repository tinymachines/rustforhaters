#!/bin/bash
# Pipeline script: process YouTube transcript and rebuild docs
# Usage: ./pipeline.sh <youtube_url> [--push] [--overwrite]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Activate Python environment
source ~/.pyenv/versions/nominate/bin/activate

# Check for URL argument
if [ -z "$1" ]; then
    echo "Usage: ./pipeline.sh <youtube_url> [--push] [--overwrite]"
    echo ""
    echo "Examples:"
    echo "  ./pipeline.sh 'https://youtu.be/VIDEO_ID'"
    echo "  ./pipeline.sh 'https://youtu.be/VIDEO_ID' --push"
    echo "  ./pipeline.sh 'https://youtu.be/VIDEO_ID' --overwrite --push"
    exit 1
fi

echo "=== Rust for Haters Pipeline ==="
echo ""

# Step 1: Process transcript
echo "[1/2] Processing transcript..."
python process_transcript.py "$@"

# Step 2: Rebuild MkDocs
echo ""
echo "[2/2] Rebuilding documentation site..."
mkdocs build --clean

echo ""
echo "=== Pipeline complete ==="
echo "View docs at: http://localhost:8764"
