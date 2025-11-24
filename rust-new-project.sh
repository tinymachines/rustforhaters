#!/usr/bin/env bash
#
# Rust Project Scaffolding Script
# Creates a new Rust project with best-practice configuration
#
# Usage: 
#   ./02-rust-new-project.sh myproject          # Binary project
#   ./02-rust-new-project.sh myproject --lib    # Library project
#   ./02-rust-new-project.sh myproject --workspace  # Workspace with bin + lib
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_create() { echo -e "${CYAN}  CREATE${NC} $1"; }

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Rust toolchain version (update as needed)
RUST_CHANNEL="stable"
RUST_VERSION="1.82.0"  # Or use "stable" / "nightly"

# Clippy lints to enforce
CLIPPY_LINTS=(
    "clippy::unwrap_used"
    "clippy::expect_used"
    "clippy::panic"
    "clippy::todo"
    "clippy::unimplemented"
    "clippy::dbg_macro"
)

CLIPPY_WARNS=(
    "clippy::pedantic"
    "clippy::nursery"
)

# -----------------------------------------------------------------------------
# File Templates
# -----------------------------------------------------------------------------

create_rust_toolchain() {
    cat << EOF
[toolchain]
channel = "${RUST_CHANNEL}"
components = ["rust-src", "rustfmt", "clippy", "rust-analyzer"]
EOF
}

create_rustfmt() {
    cat << 'EOF'
# Rust formatting configuration
# Run: cargo fmt

edition = "2021"
max_width = 100
tab_spaces = 4
newline_style = "Unix"
use_small_heuristics = "Default"

# Imports
imports_granularity = "Module"
group_imports = "StdExternalCrate"
reorder_imports = true

# Comments
wrap_comments = true
comment_width = 80
normalize_comments = true

# Misc
format_code_in_doc_comments = true
format_macro_matchers = true
EOF
}

create_clippy_toml() {
    cat << 'EOF'
# Clippy configuration
# Run: cargo clippy

# Cognitive complexity threshold
cognitive-complexity-threshold = 25

# Maximum lines in a function
too-many-lines-threshold = 100

# Maximum arguments in a function
too-many-arguments-threshold = 7

# Type complexity threshold  
type-complexity-threshold = 250
EOF
}

create_cargo_config() {
    cat << 'EOF'
# Cargo configuration
# See: https://doc.rust-lang.org/cargo/reference/config.html

[build]
# Uncomment for faster linking (requires mold: sudo apt install mold)
# rustflags = ["-C", "link-arg=-fuse-ld=mold"]

[target.x86_64-unknown-linux-gnu]
# Enable debug info in release builds for profiling
# rustflags = ["-C", "debuginfo=1"]

[alias]
# Custom cargo aliases
b = "build"
c = "check"
t = "test"
r = "run"
rr = "run --release"
br = "build --release"

# Inspection shortcuts (require nightly for some)
asm = "asm --lib"
expand = "expand"

# CI commands
ci = "clippy -- -D warnings"
EOF
}

create_gitignore() {
    cat << 'EOF'
# Rust / Cargo
/target/
Cargo.lock

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# Environment
.env
.env.local

# OS
.DS_Store
Thumbs.db

# Coverage
tarpaulin-report.html
cobertura.xml
lcov.info

# MIR dumps
mir_dump/

# Temporary files
*.tmp
*.bak
EOF
}

create_lib_rs() {
    local project_name="$1"
    cat << EOF
//! # ${project_name}
//!
//! A Rust project.

#![warn(missing_docs)]
#![warn(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]

pub mod prelude;

/// Example function demonstrating documentation.
///
/// # Examples
///
/// \`\`\`
/// use ${project_name}::add;
/// assert_eq!(add(2, 3), 5);
/// \`\`\`
#[must_use]
pub fn add(left: u64, right: u64) -> u64 {
    left + right
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_works() {
        let result = add(2, 2);
        assert_eq!(result, 4);
    }
}
EOF
}

create_main_rs() {
    local project_name="$1"
    cat << EOF
//! Binary entry point for ${project_name}
//!
//! Keep this file thin - application logic belongs in lib.rs

use ${project_name}::add;

fn main() {
    let result = add(2, 3);
    println!("2 + 3 = {result}");
}
EOF
}

create_prelude_rs() {
    cat << 'EOF'
//! Crate prelude - re-exports commonly used items
//!
//! Usage: `use crate::prelude::*;`

// Re-export common std types
pub use std::collections::{HashMap, HashSet, VecDeque};
pub use std::sync::{Arc, Mutex, RwLock};

// Re-export Result alias if you have custom error types
// pub use crate::error::{Error, Result};

// Re-export common traits from your crate
// pub use crate::traits::*;
EOF
}

create_readme() {
    local project_name="$1"
    cat << EOF
# ${project_name}

A Rust project.

## Development

### Prerequisites

- Rust toolchain (see \`rust-toolchain.toml\`)
- Recommended: \`cargo-watch\`, \`cargo-nextest\`

### Commands

\`\`\`bash
# Build
cargo build
cargo build --release

# Test
cargo test
cargo nextest run  # If installed

# Auto-rebuild on changes
cargo watch -c -x check

# Lint
cargo clippy

# Format
cargo fmt

# Documentation
cargo doc --open
\`\`\`

### Compiler Inspection

\`\`\`bash
# View macro expansion
cargo expand

# View assembly for a function
cargo asm --lib --rust function_name

# View MIR (nightly)
cargo +nightly rustc -- -Zunpretty=mir

# View type sizes (nightly)
RUSTFLAGS="-Zprint-type-sizes" cargo +nightly build
\`\`\`

## License

MIT OR Apache-2.0
EOF
}

create_cargo_toml_binary() {
    local project_name="$1"
    cat << EOF
[package]
name = "${project_name}"
version = "0.1.0"
edition = "2021"
authors = ["Your Name <you@example.com>"]
description = "A Rust project"
license = "MIT OR Apache-2.0"
readme = "README.md"

[dependencies]

[dev-dependencies]

[lints.rust]
unsafe_code = "forbid"

[lints.clippy]
# Deny these in CI
enum_glob_use = "deny"
unwrap_used = "warn"
expect_used = "warn"

# Pedantic lints (warn, not deny)
pedantic = { level = "warn", priority = -1 }
module_name_repetitions = "allow"
must_use_candidate = "allow"

[profile.dev]
# Faster incremental builds
debug = 1

[profile.release]
# Include debug symbols for profiling
debug = true
lto = "thin"

[profile.release-fast]
inherits = "release"
debug = false
lto = "fat"
codegen-units = 1
EOF
}

create_cargo_toml_lib() {
    local project_name="$1"
    cat << EOF
[package]
name = "${project_name}"
version = "0.1.0"
edition = "2021"
authors = ["Your Name <you@example.com>"]
description = "A Rust library"
license = "MIT OR Apache-2.0"
readme = "README.md"
keywords = []
categories = []

[dependencies]

[dev-dependencies]

[lints.rust]
unsafe_code = "forbid"

[lints.clippy]
enum_glob_use = "deny"
unwrap_used = "warn"
expect_used = "warn"
pedantic = { level = "warn", priority = -1 }
module_name_repetitions = "allow"
must_use_candidate = "allow"
EOF
}

create_workspace_cargo_toml() {
    local project_name="$1"
    cat << EOF
[workspace]
resolver = "2"
members = [
    "crates/${project_name}-core",
    "crates/${project_name}-cli",
]

[workspace.package]
version = "0.1.0"
edition = "2021"
authors = ["Your Name <you@example.com>"]
license = "MIT OR Apache-2.0"

[workspace.dependencies]
# Shared dependencies across workspace
# Add crates here, reference in member Cargo.toml as:
#   some-crate = { workspace = true }

[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
enum_glob_use = "deny"
unwrap_used = "warn"
expect_used = "warn"
pedantic = { level = "warn", priority = -1 }
module_name_repetitions = "allow"
must_use_candidate = "allow"
EOF
}

create_workspace_member_core() {
    local project_name="$1"
    cat << EOF
[package]
name = "${project_name}-core"
version.workspace = true
edition.workspace = true
authors.workspace = true
license.workspace = true

[dependencies]

[lints]
workspace = true
EOF
}

create_workspace_member_cli() {
    local project_name="$1"
    cat << EOF
[package]
name = "${project_name}-cli"
version.workspace = true
edition.workspace = true
authors.workspace = true
license.workspace = true

[[bin]]
name = "${project_name}"
path = "src/main.rs"

[dependencies]
${project_name}-core = { path = "../${project_name}-core" }

[lints]
workspace = true
EOF
}

# -----------------------------------------------------------------------------
# Project Creation Functions
# -----------------------------------------------------------------------------

create_binary_project() {
    local project_name="$1"
    
    log_info "Creating binary project: ${project_name}"
    
    mkdir -p "${project_name}/src"
    mkdir -p "${project_name}/.cargo"
    cd "${project_name}"
    
    # Configuration files
    log_create "Cargo.toml"
    create_cargo_toml_binary "$project_name" > Cargo.toml
    
    log_create "rust-toolchain.toml"
    create_rust_toolchain > rust-toolchain.toml
    
    log_create "rustfmt.toml"
    create_rustfmt > rustfmt.toml
    
    log_create "clippy.toml"
    create_clippy_toml > clippy.toml
    
    log_create ".cargo/config.toml"
    create_cargo_config > .cargo/config.toml
    
    log_create ".gitignore"
    create_gitignore > .gitignore
    
    log_create "README.md"
    create_readme "$project_name" > README.md
    
    # Source files
    log_create "src/lib.rs"
    create_lib_rs "$project_name" > src/lib.rs
    
    log_create "src/main.rs"
    create_main_rs "$project_name" > src/main.rs
    
    log_create "src/prelude.rs"
    create_prelude_rs > src/prelude.rs
    
    # Initialize git
    git init -q
    git add .
    
    log_ok "Binary project created at $(pwd)"
}

create_library_project() {
    local project_name="$1"
    
    log_info "Creating library project: ${project_name}"
    
    mkdir -p "${project_name}/src"
    mkdir -p "${project_name}/.cargo"
    cd "${project_name}"
    
    # Configuration files
    log_create "Cargo.toml"
    create_cargo_toml_lib "$project_name" > Cargo.toml
    
    log_create "rust-toolchain.toml"
    create_rust_toolchain > rust-toolchain.toml
    
    log_create "rustfmt.toml"
    create_rustfmt > rustfmt.toml
    
    log_create "clippy.toml"
    create_clippy_toml > clippy.toml
    
    log_create ".cargo/config.toml"
    create_cargo_config > .cargo/config.toml
    
    log_create ".gitignore"
    create_gitignore > .gitignore
    
    log_create "README.md"
    create_readme "$project_name" > README.md
    
    # Source files
    log_create "src/lib.rs"
    create_lib_rs "$project_name" > src/lib.rs
    
    log_create "src/prelude.rs"
    create_prelude_rs > src/prelude.rs
    
    # Initialize git
    git init -q
    git add .
    
    log_ok "Library project created at $(pwd)"
}

create_workspace_project() {
    local project_name="$1"
    
    log_info "Creating workspace project: ${project_name}"
    
    mkdir -p "${project_name}/crates/${project_name}-core/src"
    mkdir -p "${project_name}/crates/${project_name}-cli/src"
    mkdir -p "${project_name}/.cargo"
    cd "${project_name}"
    
    # Root configuration
    log_create "Cargo.toml (workspace)"
    create_workspace_cargo_toml "$project_name" > Cargo.toml
    
    log_create "rust-toolchain.toml"
    create_rust_toolchain > rust-toolchain.toml
    
    log_create "rustfmt.toml"
    create_rustfmt > rustfmt.toml
    
    log_create "clippy.toml"
    create_clippy_toml > clippy.toml
    
    log_create ".cargo/config.toml"
    create_cargo_config > .cargo/config.toml
    
    log_create ".gitignore"
    create_gitignore > .gitignore
    
    log_create "README.md"
    create_readme "$project_name" > README.md
    
    # Core library crate
    log_create "crates/${project_name}-core/Cargo.toml"
    create_workspace_member_core "$project_name" > "crates/${project_name}-core/Cargo.toml"
    
    log_create "crates/${project_name}-core/src/lib.rs"
    create_lib_rs "${project_name}_core" > "crates/${project_name}-core/src/lib.rs"
    
    log_create "crates/${project_name}-core/src/prelude.rs"
    create_prelude_rs > "crates/${project_name}-core/src/prelude.rs"
    
    # CLI binary crate
    log_create "crates/${project_name}-cli/Cargo.toml"
    create_workspace_member_cli "$project_name" > "crates/${project_name}-cli/Cargo.toml"
    
    log_create "crates/${project_name}-cli/src/main.rs"
    cat > "crates/${project_name}-cli/src/main.rs" << EOF
//! CLI entry point for ${project_name}

use ${project_name}_core::add;

fn main() {
    let result = add(2, 3);
    println!("2 + 3 = {result}");
}
EOF
    
    # Initialize git
    git init -q
    git add .
    
    log_ok "Workspace project created at $(pwd)"
}

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------

usage() {
    cat << EOF
Usage: $(basename "$0") <project-name> [OPTIONS]

Creates a new Rust project with best-practice configuration.

Options:
    --lib         Create a library project (no binary)
    --workspace   Create a workspace with core lib + CLI binary
    --help        Show this help message

Examples:
    $(basename "$0") myapp                  # Binary project
    $(basename "$0") mylib --lib            # Library project  
    $(basename "$0") myproj --workspace     # Workspace project

Generated structure (binary):
    myapp/
    ├── .cargo/config.toml
    ├── .gitignore
    ├── Cargo.toml
    ├── README.md
    ├── clippy.toml
    ├── rust-toolchain.toml
    ├── rustfmt.toml
    └── src/
        ├── lib.rs
        ├── main.rs
        └── prelude.rs
EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        usage
        exit 0
    fi
    
    local project_name="$1"
    local project_type="binary"
    
    # Parse options
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lib)
                project_type="library"
                ;;
            --workspace)
                project_type="workspace"
                ;;
            *)
                log_warn "Unknown option: $1"
                ;;
        esac
        shift
    done
    
    # Validate project name
    if [[ ! "$project_name" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        log_warn "Project name should be lowercase with underscores/hyphens"
    fi
    
    if [[ -d "$project_name" ]]; then
        log_error "Directory '$project_name' already exists"
        exit 1
    fi
    
    # Create project
    case "$project_type" in
        binary)
            create_binary_project "$project_name"
            ;;
        library)
            create_library_project "$project_name"
            ;;
        workspace)
            create_workspace_project "$project_name"
            ;;
    esac
    
    echo ""
    echo "Next steps:"
    echo "  cd ${project_name}"
    echo "  cargo build"
    echo "  cargo test"
    echo ""
}

main "$@"
