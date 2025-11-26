# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Rust for Haters** is an educational Rust learning tool that processes YouTube video transcripts into organized markdown documentation. The workflow:
1. Extract transcript from YouTube video URL
2. Use Claude to refactor transcript into coherent markdown
3. Organize into topic-based folders under `docs/`

## Environment Setup

```bash
# Activate Python environment
. ~/.pyenv/versions/nominate/bin/activate

# API key in .env file
ANTHROPIC_API_KEY=...
```

## Transcript Processing Tool

Main CLI tool at `process_transcript.py`:
```bash
# Process a YouTube video into markdown
python process_transcript.py "https://youtu.be/VIDEO_ID"

# Process and auto-commit/push to git
python process_transcript.py "https://youtu.be/VIDEO_ID" --push

# Overwrite existing document for same video
python process_transcript.py "https://youtu.be/VIDEO_ID" --overwrite
```

Set `AUTO_PUSH=true` in `.env` to always commit/push without the flag.

Both tools auto-regenerate `mkdocs.yml` nav and `docs/index.md` after processing.

## Sync Docs Tool

For manually-added markdown files, use `sync_docs.py`:
```bash
# Pull and organize any new markdown files
python sync_docs.py

# Pull, organize, and push
python sync_docs.py --push
```

This script:
1. Runs `git pull` to fetch new files
2. Finds uncategorized markdown files (no metadata markers)
3. Uses Claude to determine topic folder and title
4. Moves files to appropriate topic folders
5. Regenerates `mkdocs.yml` and `docs/index.md`

## Pipeline Script

Automated pipeline to process transcript and rebuild docs:
```bash
./pipeline.sh "https://youtu.be/VIDEO_ID"              # Process and rebuild
./pipeline.sh "https://youtu.be/VIDEO_ID" --push       # Also git push
./pipeline.sh "https://youtu.be/VIDEO_ID" --overwrite  # Replace existing
```

## MkDocs Documentation Server

Manual commands:
```bash
mkdocs serve                   # http://127.0.0.1:8000
mkdocs build                   # Build static site to site/
mkdocs gh-deploy               # Deploy to GitHub Pages
```

Systemd service (always-on at http://0.0.0.0:8764):
```bash
sudo ./install-service.sh                      # Install & start service
sudo systemctl status rustforhaters-docs       # Check status
sudo systemctl restart rustforhaters-docs      # Restart after changes
sudo journalctl -u rustforhaters-docs -f       # View logs
```

Config: `mkdocs.yml` | Theme: Material for MkDocs

## Rust Development Commands

```bash
# Build and run
cargo build                    # Debug build
cargo build --release          # Release build
cargo run                      # Run binary

# Testing
cargo test                     # Run all tests
cargo nextest run              # Fast parallel testing
cargo test TEST_NAME           # Run single test

# Code quality
cargo fmt                      # Format code
cargo clippy                   # Lint
cargo clippy -- -D warnings    # Strict linting

# Fast feedback loop
cargo watch -c -x check        # Auto-check on save
bacon                          # TUI for cargo watch
```

## Documentation Structure

The `docs/` folder contains educational content organized by topic folders:
- `toolchain/` - Cheatsheet, terminal development
- `syntax-and-patterns/` - Keywords and language constructs
- `memory/` - Ownership, borrowing, lifetimes
- `error-handling/` - Result, Option, unwrap
- `stdlib/` - Allocation internals (Layout, Allocator, Box, Vec)
- `rust-compiler-internals/` - Compiler architecture, MIR, LLVM

New topic folders are created automatically when processing transcripts or syncing docs.

## Shell Scripts

- `rust-env-setup.sh` - Complete Ubuntu Rust dev environment setup
- `rust-new-project.sh` - Scaffold new projects with best-practice config

## Project Conventions

When creating new transcript-based documentation:
1. Process raw transcript through Claude to create coherent markdown
2. Place in `docs/` under appropriate topic folder
3. Create new folder if transcript covers a new Rust topic
4. Follow existing documentation style (technical depth, code examples)
