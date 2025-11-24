#!/usr/bin/env bash
#
# Rust Terminal Development Environment Setup for Ubuntu
# Optimized for compiler internals study and low-level debugging
#
# Usage: chmod +x 01-rust-env-setup.sh && ./01-rust-env-setup.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# System Dependencies
# -----------------------------------------------------------------------------
install_system_deps() {
    log_info "Installing system dependencies..."
    
    sudo apt update
    sudo apt install -y \
        build-essential \
        gdb \
        lldb \
        binutils \
        pkg-config \
        libssl-dev \
        curl \
        git
    
    log_ok "System dependencies installed"
}

# -----------------------------------------------------------------------------
# Rustup and Toolchains
# -----------------------------------------------------------------------------
install_rustup() {
    if command -v rustup &> /dev/null; then
        log_info "Rustup already installed, updating..."
        rustup update
    else
        log_info "Installing rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        source "$HOME/.cargo/env"
    fi
    
    log_ok "Rustup ready"
}

setup_toolchains() {
    log_info "Setting up stable and nightly toolchains..."
    
    # Ensure both toolchains
    rustup install stable
    rustup install nightly
    rustup default stable
    
    # Components for stable
    log_info "Adding stable components..."
    rustup component add --toolchain stable \
        rust-src \
        clippy \
        rustfmt \
        rust-analyzer
    
    # Components for nightly (includes compiler internals tools)
    log_info "Adding nightly components..."
    rustup component add --toolchain nightly \
        rust-src \
        llvm-tools-preview \
        rustc-dev \
        miri \
        clippy \
        rustfmt \
        rust-analyzer
    
    log_ok "Toolchains configured"
}

# -----------------------------------------------------------------------------
# Cargo Plugins
# -----------------------------------------------------------------------------
install_cargo_plugins() {
    log_info "Installing cargo plugins..."
    
    # Core development tools
    cargo install --locked cargo-watch      # Auto-rebuild on save
    cargo install --locked bacon            # Better cargo-watch with TUI
    cargo install --locked cargo-nextest    # Faster parallel test runner
    
    # Compiler inspection tools
    cargo install --locked cargo-expand     # Macro expansion
    cargo install --locked cargo-show-asm   # View asm/llvm-ir/mir
    cargo install --locked cargo-bloat      # Binary size analysis
    
    # Security and CI/CD tools
    cargo install --locked cargo-audit      # Vulnerability scanning
    cargo install --locked cargo-deny       # Dependency policy
    cargo install --locked cargo-tarpaulin  # Test coverage
    
    # Binary inspection (rust wrappers for llvm tools)
    cargo install --locked cargo-binutils
    
    log_ok "Cargo plugins installed"
}

# -----------------------------------------------------------------------------
# Shell Configuration
# -----------------------------------------------------------------------------
setup_bash_config() {
    log_info "Setting up bash configuration..."
    
    local BASHRC="$HOME/.bashrc"
    local MARKER="# === RUST DEV ENVIRONMENT ==="
    
    # Check if already configured
    if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
        log_warn "Bash config already contains Rust setup, skipping..."
        return
    fi
    
    cat >> "$BASHRC" << 'BASHCONFIG'

# === RUST DEV ENVIRONMENT ===

# Cargo binary path
export PATH="$HOME/.cargo/bin:$PATH"

# Rust source path (for rust-analyzer and code navigation)
export RUST_SRC_PATH="$(rustc --print sysroot)/lib/rustlib/src/rust/library"

# Better backtraces
export RUST_BACKTRACE=1

# --- Aliases: Basic Cargo ---
alias cb='cargo build'
alias cbr='cargo build --release'
alias cc='cargo check'
alias cr='cargo run'
alias crr='cargo run --release'
alias ct='cargo test'
alias ctn='cargo nextest run'
alias cdoc='cargo doc --open'
alias cfmt='cargo fmt'
alias clippy='cargo clippy'

# --- Aliases: Auto-rebuild ---
alias cw='cargo watch -c -x check'
alias cwt='cargo watch -c -x test'
alias cwn='cargo watch -c -x "nextest run"'

# --- Aliases: Compiler Inspection (Nightly) ---
alias mir='cargo +nightly rustc -- -Zunpretty=mir 2>&1 | less'
alias hir='cargo +nightly rustc -- -Zunpretty=hir 2>&1 | less'
alias hir-typed='cargo +nightly rustc -- -Zunpretty=hir,typed 2>&1 | less'
alias expanded='cargo +nightly rustc -- -Zunpretty=expanded 2>&1 | less'

# --- Aliases: Assembly and LLVM IR ---
alias casm='cargo asm --lib'
alias casmr='cargo asm --lib --rust'      # Interleaved with Rust source
alias cllvm='cargo asm --lib --llvm'      # LLVM IR
alias cmir='cargo asm --lib --mir'        # MIR via cargo-show-asm

# --- Aliases: Type and Size Inspection ---
alias ctypes='RUSTFLAGS="-Zprint-type-sizes" cargo +nightly build 2>&1 | grep "print-type-size"'
alias cbloat='cargo bloat --release -n 20'

# --- Aliases: Security and CI ---
alias caudit='cargo audit'
alias cdeny='cargo deny check'
alias ccov='cargo tarpaulin --out Html && xdg-open tarpaulin-report.html'

# --- Functions ---

# Dump MIR for all optimization passes to a directory
mir_dump() {
    local dir="${1:-./mir_dump}"
    mkdir -p "$dir"
    cargo +nightly rustc -- -Zdump-mir=all -Zdump-mir-dir="$dir"
    echo "MIR dumped to $dir"
}

# Emit LLVM IR to file
llvm_ir() {
    cargo rustc --release -- --emit=llvm-ir -C debuginfo=0 -C codegen-units=1
    local ir_file=$(find target/release/deps -name "*.ll" -type f | head -1)
    if [[ -n "$ir_file" ]]; then
        echo "LLVM IR at: $ir_file"
        less "$ir_file"
    fi
}

# Emit assembly to file
emit_asm() {
    cargo rustc --release -- --emit=asm -C llvm-args=-x86-asm-syntax=intel
    local asm_file=$(find target/release/deps -name "*.s" -type f | head -1)
    if [[ -n "$asm_file" ]]; then
        echo "Assembly at: $asm_file"
        less "$asm_file"
    fi
}

# Search std library source
std_search() {
    local query="$1"
    rg "$query" --type rust "$(rustc --print sysroot)/lib/rustlib/src/rust/library/"
}

# Quick project stats
rust_stats() {
    echo "=== Rust Environment ==="
    echo "rustc: $(rustc --version)"
    echo "cargo: $(cargo --version)"
    echo "rustup: $(rustup --version 2>/dev/null | head -1)"
    echo ""
    echo "=== Installed Toolchains ==="
    rustup toolchain list
    echo ""
    echo "=== Default Components ==="
    rustup component list --installed | head -10
}

# === END RUST DEV ENVIRONMENT ===
BASHCONFIG

    log_ok "Bash configuration added to $BASHRC"
}

setup_bash_completions() {
    log_info "Setting up shell completions..."
    
    local COMP_DIR="$HOME/.local/share/bash-completion/completions"
    mkdir -p "$COMP_DIR"
    
    rustup completions bash > "$COMP_DIR/rustup"
    rustup completions bash cargo > "$COMP_DIR/cargo"
    
    log_ok "Completions installed to $COMP_DIR"
}

# -----------------------------------------------------------------------------
# Vim Setup
# -----------------------------------------------------------------------------
setup_vim() {
    log_info "Setting up minimal Vim configuration for Rust..."
    
    # Install rust.vim plugin
    local VIM_PLUGIN_DIR="$HOME/.vim/pack/plugins/start"
    mkdir -p "$VIM_PLUGIN_DIR"
    
    if [[ -d "$VIM_PLUGIN_DIR/rust.vim" ]]; then
        log_info "rust.vim already installed, updating..."
        git -C "$VIM_PLUGIN_DIR/rust.vim" pull
    else
        git clone https://github.com/rust-lang/rust.vim "$VIM_PLUGIN_DIR/rust.vim"
    fi
    
    # Create/update vimrc
    local VIMRC="$HOME/.vimrc"
    local MARKER='" === RUST CONFIG ==='
    
    if grep -q "$MARKER" "$VIMRC" 2>/dev/null; then
        log_warn "Vim already has Rust config, skipping..."
        return
    fi
    
    cat >> "$VIMRC" << 'VIMCONFIG'

" === RUST CONFIG ===

syntax enable
filetype plugin indent on

" General settings
set number relativenumber
set expandtab tabstop=4 shiftwidth=4
set hidden
set updatetime=300
set signcolumn=yes
set backspace=indent,eol,start

" Search
set incsearch hlsearch ignorecase smartcase

" rust.vim: format on save
let g:rustfmt_autosave = 1

" Cargo compiler integration
autocmd FileType rust compiler cargo
autocmd QuickFixCmdPost [^l]* nested cwindow

" Key mappings for cargo commands
nnoremap <leader>b :make build<CR>
nnoremap <leader>r :make run<CR>
nnoremap <leader>t :make test<CR>
nnoremap <leader>c :make check<CR>

" Quickfix navigation
nnoremap ]q :cnext<CR>
nnoremap [q :cprev<CR>
nnoremap ]Q :clast<CR>
nnoremap [Q :cfirst<CR>

" Quick save
nnoremap <leader>w :w<CR>

" Clear search highlight
nnoremap <leader><space> :nohlsearch<CR>

" === END RUST CONFIG ===
VIMCONFIG

    log_ok "Vim configured with rust.vim"
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
verify_installation() {
    log_info "Verifying installation..."
    
    echo ""
    echo "=== Toolchain Versions ==="
    rustc --version
    cargo --version
    rustup --version 2>/dev/null | head -1
    
    echo ""
    echo "=== Installed Cargo Plugins ==="
    for cmd in bacon cargo-nextest cargo-expand cargo-show-asm cargo-audit cargo-deny cargo-tarpaulin; do
        if command -v "$cmd" &> /dev/null || cargo help "$cmd" &> /dev/null 2>&1; then
            echo "  ✓ $cmd"
        else
            echo "  ✗ $cmd (missing)"
        fi
    done
    
    echo ""
    echo "=== System Tools ==="
    for cmd in gdb lldb objdump readelf nm; do
        if command -v "$cmd" &> /dev/null; then
            echo "  ✓ $cmd"
        else
            echo "  ✗ $cmd (missing)"
        fi
    done
    
    echo ""
    log_ok "Verification complete"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Rust Terminal Development Environment Setup              ║"
    echo "║     Optimized for Compiler Internals & Low-Level Debugging   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    install_system_deps
    install_rustup
    setup_toolchains
    install_cargo_plugins
    setup_bash_config
    setup_bash_completions
    setup_vim
    verify_installation
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Setup Complete!                           ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Reload your shell:  source ~/.bashrc                        ║"
    echo "║  Or start a new terminal session                             ║"
    echo "║                                                              ║"
    echo "║  Quick test:  rust_stats                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

main "$@"
