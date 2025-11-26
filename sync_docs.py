#!/usr/bin/env python3
"""
Sync and organize manually-added markdown files in docs/.

Usage:
    python sync_docs.py [--push]
    python sync_docs.py --delete <path-to-file> [--push]

This script:
1. Executes git pull to get any new files (and detects deleted files)
2. Finds markdown files not yet categorized (in docs/ root or lacking metadata)
3. Uses Claude to determine topic and proper title
4. Moves files to appropriate topic folders
5. Regenerates mkdocs.yml and index.md

Delete mode:
    --delete <path>  Delete a doc file and update navigation
"""

import sys
import os
import re
import subprocess
from pathlib import Path
from dotenv import load_dotenv
import anthropic

# Import shared functions from process_transcript
from process_transcript import (
    regenerate_mkdocs_nav,
    regenerate_index,
    git_commit_and_push,
)


def git_pull(project_root: Path) -> tuple[bool, list[str]]:
    """Execute git pull and return (had_changes, deleted_files)."""
    print("Pulling latest changes...")

    # Get list of files before pull
    try:
        result = subprocess.run(
            ["git", "pull"],
            check=True,
            capture_output=True,
            text=True,
            cwd=project_root
        )
        output = result.stdout.strip()
        print(output if output else "Already up to date.")

        # Parse deleted files from pull output
        # Lines like: "delete mode 100644 docs/some-file.md"
        deleted = []
        for line in output.split('\n'):
            if 'delete mode' in line and 'docs/' in line:
                # Extract the file path
                parts = line.split()
                if len(parts) >= 4:
                    deleted.append(parts[-1])

        had_changes = "Already up to date" not in output
        return had_changes, deleted

    except subprocess.CalledProcessError as e:
        print(f"Git pull failed: {e.stderr}")
        return False, []


def delete_doc(filepath: Path, docs_dir: Path, project_root: Path, auto_push: bool):
    """Delete a document file and update navigation."""
    if not filepath.exists():
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    if not str(filepath).startswith(str(docs_dir)):
        print(f"Error: File must be within docs/ directory")
        sys.exit(1)

    rel_path = filepath.relative_to(project_root)
    print(f"Deleting: {rel_path}")

    # Remove the file
    filepath.unlink()

    # Check if parent folder is now empty (except for README/index)
    parent = filepath.parent
    if parent != docs_dir:
        remaining = [f for f in parent.iterdir()
                     if f.name not in ('README.md', 'index.md', '.DS_Store')]
        if not remaining:
            # Remove README/index if present
            for special in ('README.md', 'index.md'):
                special_path = parent / special
                if special_path.exists():
                    special_path.unlink()
            # Remove empty folder
            parent.rmdir()
            print(f"Removed empty folder: {parent.name}/")

    # Regenerate nav
    regenerate_mkdocs_nav(docs_dir, project_root)
    regenerate_index(docs_dir)

    # Git commit if enabled
    if auto_push:
        try:
            subprocess.run(
                ["git", "add", "-A", "docs/", "mkdocs.yml"],
                check=True,
                capture_output=True,
                cwd=project_root
            )
            subprocess.run(
                ["git", "commit", "-m", f"Remove doc: {rel_path.name}"],
                check=True,
                capture_output=True,
                cwd=project_root
            )
            subprocess.run(
                ["git", "push"],
                check=True,
                capture_output=True,
                cwd=project_root
            )
            print("Committed and pushed.")
        except subprocess.CalledProcessError as e:
            print(f"Git error: {e.stderr.decode() if e.stderr else e}")


def find_uncategorized_docs(docs_dir: Path) -> list[Path]:
    """Find markdown files in docs/ root that should be categorized."""
    uncategorized = []

    # Files to skip (special files that should stay at root)
    skip_files = {'index.md', 'README.md'}

    for md_file in docs_dir.glob("*.md"):
        if md_file.name in skip_files:
            continue

        # Check if file has VideoId metadata (already processed)
        content = md_file.read_text()
        if "<!-- VideoId:" in content:
            continue

        # Check if file has ProcessedBy metadata (already processed by this script)
        if "<!-- ProcessedBy: sync_docs -->" in content:
            continue

        uncategorized.append(md_file)

    return uncategorized


def categorize_with_claude(filepath: Path, client: anthropic.Anthropic) -> dict:
    """Use Claude to determine topic and title for a markdown file."""
    print(f"Analyzing: {filepath.name}")

    content = filepath.read_text()

    # Truncate if too long
    if len(content) > 50000:
        content = content[:50000] + "\n\n[Content truncated...]"

    prompt = f"""Analyze this Rust-related markdown document and categorize it.

<document>
{content}
</document>

Determine:
1. The main topic category. Choose from existing topics or suggest a new one:
   - toolchain (rustup, rustc, cargo, build system)
   - syntax-and-patterns (keywords, syntax, pattern matching)
   - memory (ownership, borrowing, lifetimes, references)
   - stdlib (standard library, collections, iterators)
   - error-handling (Result, Option, error types)
   - concurrency (threads, async, channels)
   - unsafe (unsafe Rust, FFI, raw pointers)
   - testing (unit tests, integration tests, benchmarks)
   - rust-compiler-internals (compiler architecture, MIR, LLVM)
   - Or suggest a new topic name (lowercase, hyphenated)

2. A clear, concise title for the document (if the existing H1 is good, keep it)

3. A suggested filename (lowercase, hyphenated, .md extension)

Respond in this exact format:
TOPIC: <topic-name>
TITLE: <document-title>
FILENAME: <suggested-filename.md>
"""

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}]
    )

    response_text = message.content[0].text

    # Parse response
    topic = None
    title = None
    filename = None

    for line in response_text.split('\n'):
        if line.startswith('TOPIC:'):
            topic = line.replace('TOPIC:', '').strip().lower()
        elif line.startswith('TITLE:'):
            title = line.replace('TITLE:', '').strip()
        elif line.startswith('FILENAME:'):
            filename = line.replace('FILENAME:', '').strip()

    return {
        'topic': topic or 'misc',
        'title': title or filepath.stem.replace('-', ' ').title(),
        'filename': filename or filepath.name
    }


def move_and_update_doc(filepath: Path, result: dict, docs_dir: Path) -> Path:
    """Move document to topic folder and update its metadata."""
    topic = result['topic']
    filename = result['filename']
    title = result['title']

    # Create topic folder if needed
    topic_dir = docs_dir / topic
    topic_dir.mkdir(parents=True, exist_ok=True)

    # Read current content
    content = filepath.read_text()

    # Update H1 title if different
    h1_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
    if h1_match and h1_match.group(1).strip() != title:
        content = re.sub(r'^#\s+.+$', f'# {title}', content, count=1, flags=re.MULTILINE)
    elif not h1_match:
        content = f'# {title}\n\n{content}'

    # Add metadata marker
    if "<!-- ProcessedBy:" not in content:
        content = f"{content}\n\n<!-- ProcessedBy: sync_docs -->\n"

    # Determine new path
    new_path = topic_dir / filename

    # Handle duplicates
    counter = 1
    while new_path.exists() and new_path != filepath:
        stem = filename.rsplit('.', 1)[0]
        new_path = topic_dir / f"{stem}-{counter}.md"
        counter += 1

    # Move file
    if new_path != filepath:
        new_path.write_text(content)
        filepath.unlink()
        print(f"  Moved to: {new_path.relative_to(docs_dir.parent)}")
    else:
        filepath.write_text(content)
        print(f"  Updated in place: {filepath.relative_to(docs_dir.parent)}")

    return new_path


def git_commit_sync(moved_files: list[tuple[Path, Path]], project_root: Path):
    """Git add, commit the synced files."""
    print("\nCommitting changes...")

    try:
        # Stage all changes in docs/ and mkdocs.yml
        subprocess.run(
            ["git", "add", "docs/", "mkdocs.yml"],
            check=True,
            capture_output=True,
            cwd=project_root
        )

        # Check if there are changes to commit
        result = subprocess.run(
            ["git", "diff", "--cached", "--quiet"],
            capture_output=True,
            cwd=project_root
        )

        if result.returncode == 0:
            print("No changes to commit.")
            return

        # Build commit message
        if len(moved_files) == 1:
            _, new_path = moved_files[0]
            commit_msg = f"Organize doc: {new_path.name}"
        else:
            commit_msg = f"Organize {len(moved_files)} docs into topic folders"

        subprocess.run(
            ["git", "commit", "-m", commit_msg],
            check=True,
            capture_output=True,
            cwd=project_root
        )
        print(f"Committed: {commit_msg}")

        # Push
        subprocess.run(
            ["git", "push"],
            check=True,
            capture_output=True,
            cwd=project_root
        )
        print("Pushed to remote.")

    except subprocess.CalledProcessError as e:
        print(f"Git error: {e.stderr.decode() if e.stderr else e}")


def main():
    # Parse arguments
    args = sys.argv[1:]
    push_flag = '--push' in args
    delete_flag = '--delete' in args

    # Load environment
    load_dotenv()

    auto_push = push_flag or os.getenv('AUTO_PUSH', '').lower() in ('true', '1', 'yes')

    # Setup paths
    project_root = Path(__file__).parent
    docs_dir = project_root / "docs"

    # Handle --delete mode
    if delete_flag:
        try:
            delete_idx = args.index('--delete')
            if delete_idx + 1 >= len(args) or args[delete_idx + 1].startswith('-'):
                print("Error: --delete requires a file path")
                print("Usage: python sync_docs.py --delete <path-to-file> [--push]")
                sys.exit(1)
            filepath = Path(args[delete_idx + 1])
            if not filepath.is_absolute():
                filepath = project_root / filepath
            delete_doc(filepath, docs_dir, project_root, auto_push)
            return
        except ValueError:
            pass

    # Need API key for categorization
    api_key = os.getenv('ANTHROPIC_API_KEY')
    if not api_key:
        print("Error: ANTHROPIC_API_KEY not found in .env file")
        sys.exit(1)

    # Git pull first
    had_changes, deleted_files = git_pull(project_root)

    # Report any files deleted remotely
    if deleted_files:
        print(f"\nDetected {len(deleted_files)} file(s) deleted remotely:")
        for f in deleted_files:
            print(f"  - {f}")

    # Find uncategorized docs
    uncategorized = find_uncategorized_docs(docs_dir)

    if not uncategorized:
        print("\nNo new uncategorized documents found.")
        # Still regenerate nav in case structure changed
        regenerate_mkdocs_nav(docs_dir, project_root)
        regenerate_index(docs_dir)
        print("Navigation updated.")
        return

    print(f"\nFound {len(uncategorized)} uncategorized document(s):")
    for f in uncategorized:
        print(f"  - {f.name}")

    # Process each file
    client = anthropic.Anthropic(api_key=api_key)
    moved_files = []

    print()
    for filepath in uncategorized:
        result = categorize_with_claude(filepath, client)
        print(f"  Topic: {result['topic']}")
        print(f"  Title: {result['title']}")

        new_path = move_and_update_doc(filepath, result, docs_dir)
        moved_files.append((filepath, new_path))
        print()

    # Regenerate mkdocs.yml and index.md
    regenerate_mkdocs_nav(docs_dir, project_root)
    regenerate_index(docs_dir)

    print(f"\nProcessed {len(moved_files)} document(s).")

    # Git commit and push if enabled
    if auto_push and moved_files:
        git_commit_sync(moved_files, project_root)


if __name__ == "__main__":
    main()
