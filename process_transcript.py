#!/usr/bin/env python3
"""
CLI tool to process YouTube transcripts into organized Rust learning markdown.

Usage:
    python process_transcript.py <youtube_url> [--push] [--overwrite]

Examples:
    python process_transcript.py "https://youtu.be/QQzAWxYKPSE"
    python process_transcript.py "https://youtu.be/QQzAWxYKPSE" --push
    python process_transcript.py "https://youtu.be/QQzAWxYKPSE" --overwrite

Options:
    --push       Git add, commit, and push after saving (can also set AUTO_PUSH=true in .env)
    --overwrite  Overwrite existing document if video was already processed
"""

import sys
import os
import re
import subprocess
from pathlib import Path
from dotenv import load_dotenv
import anthropic
import yaml

# Add the youtube transcript api to path
sys.path.insert(0, str(Path(__file__).parent / "external" / "youtube-transcript-api"))
from youtube_transcript_api import YouTubeTranscriptApi


def extract_video_id(url: str) -> str:
    """Extract YouTube video ID from various URL formats."""
    patterns = [
        r'youtu\.be/([a-zA-Z0-9_-]{11})',           # youtu.be/ID
        r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})', # youtube.com/watch?v=ID
        r'youtube\.com/embed/([a-zA-Z0-9_-]{11})',   # youtube.com/embed/ID
        r'youtube\.com/v/([a-zA-Z0-9_-]{11})',       # youtube.com/v/ID
        r'^([a-zA-Z0-9_-]{11})$',                    # Just the ID
    ]

    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)

    raise ValueError(f"Could not extract video ID from: {url}")


def find_existing_document(video_id: str, docs_dir: Path) -> Path | None:
    """Check if a document with this video ID already exists."""
    if not docs_dir.exists():
        return None

    for md_file in docs_dir.rglob("*.md"):
        try:
            content = md_file.read_text()
            if f"<!-- VideoId: {video_id} -->" in content:
                return md_file
        except Exception:
            continue

    return None


def fetch_transcript(video_id: str) -> str:
    """Fetch transcript from YouTube."""
    print(f"Fetching transcript for video: {video_id}")

    api = YouTubeTranscriptApi()
    transcript_parts = []

    for snippet in api.fetch(video_id):
        transcript_parts.append(snippet.text)

    return " ".join(transcript_parts)


def process_with_claude(transcript: str, client: anthropic.Anthropic) -> dict:
    """Send transcript to Claude for processing."""
    print("Processing transcript with Claude...")

    prompt = f"""You are helping create educational Rust documentation from a YouTube video transcript.

Here is the raw transcript:

<transcript>
{transcript}
</transcript>

Please do the following:

1. First, determine if this transcript is about Rust programming. If not, indicate that clearly.

2. If it IS about Rust, identify the main topic. Choose from existing topics or suggest a new one:
   - toolchain (rustup, rustc, cargo, build system)
   - syntax-and-patterns (keywords, syntax, pattern matching)
   - memory (ownership, borrowing, lifetimes, references)
   - stdlib (standard library, collections, iterators)
   - error-handling (Result, Option, error types)
   - concurrency (threads, async, channels)
   - unsafe (unsafe Rust, FFI, raw pointers)
   - testing (unit tests, integration tests, benchmarks)
   - Or suggest a new topic name (lowercase, hyphenated)

3. Create a well-organized markdown document from the transcript content:
   - Use clear headings and subheadings
   - Include code examples where mentioned
   - Fix any transcription errors or unclear passages
   - Organize the content logically (it may not be in order in the transcript)
   - Add technical accuracy and clarity
   - Keep the educational tone

Respond in this exact format:

TOPIC: <topic-name>
TITLE: <document-title>
IS_RUST: <yes/no>

---CONTENT---
<the markdown content>
"""

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=8192,
        messages=[
            {"role": "user", "content": prompt}
        ]
    )

    response_text = message.content[0].text

    # Parse the response
    lines = response_text.split('\n')
    topic = None
    title = None
    is_rust = True
    content_start = 0

    for i, line in enumerate(lines):
        if line.startswith('TOPIC:'):
            topic = line.replace('TOPIC:', '').strip().lower()
        elif line.startswith('TITLE:'):
            title = line.replace('TITLE:', '').strip()
        elif line.startswith('IS_RUST:'):
            is_rust = 'yes' in line.lower()
        elif '---CONTENT---' in line:
            content_start = i + 1
            break

    content = '\n'.join(lines[content_start:]).strip()

    return {
        'topic': topic or 'misc',
        'title': title or 'Untitled',
        'is_rust': is_rust,
        'content': content
    }


def save_document(result: dict, docs_dir: Path, video_id: str, existing_path: Path | None = None) -> Path:
    """Save the processed document to the appropriate folder."""
    topic = result['topic']
    title = result['title']
    content = result['content']

    # Append video ID metadata
    content = f"{content}\n\n<!-- VideoId: {video_id} -->\n"

    # If overwriting, use existing path
    if existing_path:
        existing_path.write_text(content)
        return existing_path

    # Create topic folder if needed
    topic_dir = docs_dir / topic
    topic_dir.mkdir(parents=True, exist_ok=True)

    # Generate filename from title
    filename = re.sub(r'[^\w\s-]', '', title.lower())
    filename = re.sub(r'[-\s]+', '-', filename).strip('-')
    filename = f"{filename}.md"

    filepath = topic_dir / filename

    # Handle duplicates
    counter = 1
    while filepath.exists():
        filepath = topic_dir / f"{filename[:-3]}-{counter}.md"
        counter += 1

    filepath.write_text(content)
    return filepath


def get_doc_title(filepath: Path) -> str:
    """Extract title from markdown file (first H1 or filename)."""
    try:
        content = filepath.read_text()
        # Look for first H1 heading
        match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
        if match:
            return match.group(1).strip()
    except Exception:
        pass
    # Fallback to filename
    return filepath.stem.replace('-', ' ').title()


def prettify_topic_name(topic: str) -> str:
    """Convert topic folder name to display name."""
    special_cases = {
        'stdlib': 'Standard Library',
        'rust-compiler-internals': 'Compiler Internals',
    }
    if topic in special_cases:
        return special_cases[topic]
    return topic.replace('-', ' ').title()


# Source file extensions to include in docs
SOURCE_EXTENSIONS = {'.rs', '.py', '.c', '.cpp', '.go', '.js', '.ts'}

# Map extensions to markdown code fence language
LANG_MAP = {
    '.rs': 'rust',
    '.py': 'python',
    '.c': 'c',
    '.cpp': 'cpp',
    '.go': 'go',
    '.js': 'javascript',
    '.ts': 'typescript',
}


def get_source_title(filepath: Path) -> str:
    """Generate a title for a source file."""
    return filepath.name


def get_wrapper_name(src_file: Path) -> str:
    """Get wrapper filename: foo.rs -> foo-src.md"""
    return src_file.stem + '-src.md'


def generate_source_wrapper(src_file: Path) -> Path:
    """Generate a markdown wrapper for a source file with syntax highlighting."""
    lang = LANG_MAP.get(src_file.suffix, '')
    content = src_file.read_text()

    md_content = f"""# {src_file.name}

```{lang}
{content}
```
"""
    wrapper_path = src_file.parent / get_wrapper_name(src_file)
    wrapper_path.write_text(md_content)
    return wrapper_path


# Folders to ignore in docs
IGNORE_FOLDERS = {'repo', '__pycache__', '.git'}


def build_lecture_series_nav(series_dir: Path, base_path: str) -> list:
    """Build nav structure for a lecture series (e.g., docs/lectures/ripgrep/)."""
    items = []

    # Series index
    index = series_dir / "index.md"
    if index.exists():
        items.append({'Overview': f"{base_path}/index.md"})

    # Lectures subfolder
    lectures_dir = series_dir / "lectures"
    if lectures_dir.exists():
        lecture_items = []
        for md_file in sorted(lectures_dir.glob("*.md")):
            title = get_doc_title(md_file)
            lecture_items.append({title: f"{base_path}/lectures/{md_file.name}"})
        if lecture_items:
            items.append({'Lectures': lecture_items})

    # Companions subfolder
    companions_dir = series_dir / "companions"
    if companions_dir.exists():
        companion_items = []
        for md_file in sorted(companions_dir.glob("*.md")):
            title = get_doc_title(md_file)
            companion_items.append({title: f"{base_path}/companions/{md_file.name}"})
        if companion_items:
            items.append({'Companions': companion_items})

    # Samples subfolder (if exists)
    samples_dir = series_dir / "samples"
    if samples_dir.exists():
        sample_items = []
        for md_file in sorted(samples_dir.glob("*.md")):
            if md_file.name == 'index.md':
                continue
            title = get_doc_title(md_file)
            sample_items.append({title: f"{base_path}/samples/{md_file.name}"})
        if sample_items:
            items.append({'Samples': sample_items})

    return items


def build_lectures_nav(lectures_dir: Path) -> dict:
    """Build nav structure for the entire lectures folder."""
    lecture_series = []

    for series in sorted(lectures_dir.iterdir()):
        if not series.is_dir() or series.name in IGNORE_FOLDERS:
            continue

        # Check if this is a valid lecture series (has index.md or lectures/ subfolder)
        has_index = (series / "index.md").exists()
        has_lectures = (series / "lectures").exists()

        if has_index or has_lectures:
            series_name = prettify_topic_name(series.name)
            series_items = build_lecture_series_nav(series, f"lectures/{series.name}")
            if series_items:
                lecture_series.append({series_name: series_items})

    return {'Lectures': lecture_series} if lecture_series else None


def regenerate_mkdocs_nav(docs_dir: Path, project_root: Path):
    """Regenerate mkdocs.yml nav section based on docs directory structure."""
    print("Regenerating mkdocs.yml navigation...")

    mkdocs_path = project_root / "mkdocs.yml"
    if not mkdocs_path.exists():
        print("Warning: mkdocs.yml not found")
        return

    # Read current mkdocs.yml
    with open(mkdocs_path) as f:
        config = yaml.safe_load(f)

    # Build new nav structure
    nav = []

    # Always start with Home
    nav.append({'Home': 'index.md'})

    # Collect top-level docs (non-index)
    top_level = []
    folders = []

    for item in sorted(docs_dir.iterdir()):
        if item.name == 'index.md':
            continue
        if item.is_file() and item.suffix == '.md':
            title = get_doc_title(item)
            top_level.append((title, item.name))
        elif item.is_dir() and item.name not in IGNORE_FOLDERS:
            folders.append(item)

    # Add top-level docs
    for title, filename in top_level:
        nav.append({title: filename})

    # Add folder sections
    for folder in sorted(folders):
        # Special handling for lectures
        if folder.name == 'lectures':
            lectures_nav = build_lectures_nav(folder)
            if lectures_nav:
                nav.append(lectures_nav)
            continue
        section_name = prettify_topic_name(folder.name)
        section_items = []

        # Check for README or index first
        readme = folder / "README.md"
        index = folder / "index.md"

        if readme.exists():
            section_items.append({'Overview': f"{folder.name}/README.md"})
        elif index.exists():
            section_items.append({'Overview': f"{folder.name}/index.md"})

        # Add other markdown files (exclude source wrappers like foo-src.md)
        for md_file in sorted(folder.glob("*.md")):
            if md_file.name in ('README.md', 'index.md'):
                continue
            # Skip source file wrappers (e.g., foo-src.md)
            if md_file.name.endswith('-src.md'):
                continue
            title = get_doc_title(md_file)
            section_items.append({title: f"{folder.name}/{md_file.name}"})

        # Add source files (generate markdown wrappers)
        source_files = []
        for src_file in sorted(folder.iterdir()):
            if src_file.is_file() and src_file.suffix in SOURCE_EXTENSIONS:
                # Generate markdown wrapper
                wrapper_path = generate_source_wrapper(src_file)
                title = get_source_title(src_file)
                # Link to the markdown wrapper (readable with syntax highlighting)
                source_files.append({title: f"{folder.name}/{wrapper_path.name}"})

        if source_files:
            section_items.append({'Source Files': source_files})

        if section_items:
            nav.append({section_name: section_items})

    # Update config
    config['nav'] = nav

    # Ensure repo folders are excluded from docs
    if 'exclude_docs' not in config:
        config['exclude_docs'] = "**/repo/**\n**/__pycache__/**"

    # Write back
    with open(mkdocs_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f"Updated mkdocs.yml with {len(nav)} nav entries")


def regenerate_index(docs_dir: Path):
    """Regenerate docs/index.md based on current documentation structure."""
    print("Regenerating index.md...")

    index_path = docs_dir / "index.md"

    # Collect structure
    top_level = []
    sections = {}  # section_name -> {'docs': [...], 'sources': [...]}
    lecture_series = []  # list of (series_name, index_path, lecture_count)

    for item in sorted(docs_dir.iterdir()):
        if item.name == 'index.md':
            continue
        if item.is_file() and item.suffix == '.md':
            title = get_doc_title(item)
            top_level.append((title, item.name))
        elif item.is_dir() and item.name not in IGNORE_FOLDERS:
            # Special handling for lectures
            if item.name == 'lectures':
                for series in sorted(item.iterdir()):
                    if not series.is_dir() or series.name in IGNORE_FOLDERS:
                        continue
                    series_index = series / "index.md"
                    lectures_subdir = series / "lectures"
                    if series_index.exists() or lectures_subdir.exists():
                        series_name = prettify_topic_name(series.name)
                        lecture_count = len(list(lectures_subdir.glob("*.md"))) if lectures_subdir.exists() else 0
                        index_link = f"lectures/{series.name}/index.md" if series_index.exists() else None
                        lecture_series.append((series_name, index_link, lecture_count))
                continue

            section_name = prettify_topic_name(item.name)
            docs = []
            sources = []

            for md_file in sorted(item.glob("*.md")):
                if md_file.name in ('README.md', 'index.md'):
                    continue
                # Skip source file wrappers (e.g., foo-src.md)
                if md_file.name.endswith('-src.md'):
                    continue
                title = get_doc_title(md_file)
                docs.append((title, f"{item.name}/{md_file.name}"))

            for src_file in sorted(item.iterdir()):
                if src_file.is_file() and src_file.suffix in SOURCE_EXTENSIONS:
                    # src = raw file, doc = markdown wrapper (foo-src.md)
                    src_path = f"{item.name}/{src_file.name}"
                    doc_path = f"{item.name}/{get_wrapper_name(src_file)}"
                    sources.append((src_file.name, src_path, doc_path))

            if docs or sources:
                sections[section_name] = {'docs': docs, 'sources': sources}

    # Generate markdown
    lines = [
        "# Rust for Haters",
        "",
        "Welcome to **Rust for Haters** - educational Rust documentation generated from YouTube video transcripts.",
        "",
        "## Topics",
        "",
    ]

    # Add top-level docs
    for title, filename in top_level:
        lines.append(f"- **[{title}]({filename})**")

    # Add sections
    if sections:
        lines.append("")
        lines.append("## Deep Dives")
        lines.append("")
        for section_name, content in sections.items():
            lines.append(f"### {section_name}")
            lines.append("")
            for title, path in content['docs']:
                lines.append(f"- [{title}]({path})")
            if content['sources']:
                lines.append("")
                lines.append("**Source Files:**")
                for name, src_path, doc_path in content['sources']:
                    lines.append(f"- `{name}` [[src]]({src_path}) [[doc]]({doc_path})")
            lines.append("")

    # Add lecture series
    if lecture_series:
        lines.append("")
        lines.append("## Lecture Series")
        lines.append("")
        for series_name, index_link, lecture_count in lecture_series:
            if index_link:
                lines.append(f"- **[{series_name}]({index_link})** — {lecture_count} lectures")
            else:
                lines.append(f"- **{series_name}** — {lecture_count} lectures")
        lines.append("")

    # Add footer
    lines.extend([
        "## Contributing",
        "",
        "New documentation is generated using the transcript processing tool:",
        "",
        "```bash",
        'python process_transcript.py "https://youtu.be/VIDEO_ID" --push',
        "```",
        "",
    ])

    index_path.write_text('\n'.join(lines))
    print(f"Updated index.md")


def git_commit_and_push(filepath: Path, title: str, video_id: str, project_root: Path):
    """Git add, commit, and push the new document."""
    print("\nCommitting to git...")

    try:
        # Get relative path for cleaner commit message
        rel_path = filepath.relative_to(project_root)

        # Git add - include the doc, mkdocs.yml, and index.md
        subprocess.run(
            ["git", "add", str(filepath), "mkdocs.yml", "docs/index.md"],
            check=True,
            capture_output=True,
            cwd=project_root
        )

        # Git commit
        commit_msg = f"Add transcript: {title}\n\nSource: https://youtu.be/{video_id}"
        subprocess.run(
            ["git", "commit", "-m", commit_msg],
            check=True,
            capture_output=True
        )
        print(f"Committed: {rel_path}")

        # Git push
        result = subprocess.run(
            ["git", "push"],
            check=True,
            capture_output=True,
            text=True
        )
        print("Pushed to remote.")

    except subprocess.CalledProcessError as e:
        print(f"Git error: {e.stderr.decode() if e.stderr else e}")
        raise


def main():
    # Parse arguments
    args = sys.argv[1:]
    push_flag = '--push' in args
    overwrite_flag = '--overwrite' in args
    args = [a for a in args if a not in ('--push', '--overwrite')]

    if len(args) < 1:
        print("Usage: python process_transcript.py <youtube_url> [--push] [--overwrite]")
        print("Example: python process_transcript.py 'https://youtu.be/QQzAWxYKPSE' --push")
        sys.exit(1)

    url = args[0]

    # Load environment
    load_dotenv()
    api_key = os.getenv('ANTHROPIC_API_KEY')
    if not api_key:
        print("Error: ANTHROPIC_API_KEY not found in .env file")
        sys.exit(1)

    # Check if auto-push is enabled (command line flag overrides env)
    auto_push = push_flag or os.getenv('AUTO_PUSH', '').lower() in ('true', '1', 'yes')

    # Setup paths
    project_root = Path(__file__).parent
    docs_dir = project_root / "docs"

    try:
        # Extract video ID
        video_id = extract_video_id(url)
        print(f"Video ID: {video_id}")

        # Check for existing document
        existing_doc = find_existing_document(video_id, docs_dir)
        if existing_doc and not overwrite_flag:
            print(f"\nError: This video has already been processed.")
            print(f"Existing document: {existing_doc}")
            print("\nUse --overwrite to replace the existing document.")
            sys.exit(1)
        elif existing_doc:
            print(f"Will overwrite existing document: {existing_doc}")

        # Fetch transcript
        transcript = fetch_transcript(video_id)
        print(f"Transcript length: {len(transcript)} characters")

        if len(transcript) < 100:
            print("Warning: Transcript seems very short. Video may not have captions.")

        # Process with Claude
        client = anthropic.Anthropic(api_key=api_key)
        result = process_with_claude(transcript, client)

        if not result['is_rust']:
            print("\nWarning: This video doesn't appear to be about Rust programming.")
            response = input("Continue anyway? (y/n): ")
            if response.lower() != 'y':
                print("Aborted.")
                sys.exit(0)

        # Save document
        filepath = save_document(result, docs_dir, video_id, existing_doc)

        print(f"\nSuccess!")
        print(f"Topic: {result['topic']}")
        print(f"Title: {result['title']}")
        print(f"Saved to: {filepath}")

        # Regenerate mkdocs.yml and index.md
        regenerate_mkdocs_nav(docs_dir, project_root)
        regenerate_index(docs_dir)

        # Git commit and push if enabled
        if auto_push:
            git_commit_and_push(filepath, result['title'], video_id, project_root)

    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        raise


if __name__ == "__main__":
    main()
