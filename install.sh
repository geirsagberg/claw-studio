#!/usr/bin/env bash
# Claw Studio installer
# Usage: curl -fsSL https://raw.githubusercontent.com/perweum/claw-studio/main/install.sh | bash

set -euo pipefail

CLAW_REPO="https://github.com/perweum/claw-studio.git"
NANOCLAW_REPO="https://github.com/nanoclaw-ai/nanoclaw.git"
NANOCLAW_DIR="$HOME/nanoclaw"
STUDIO_DIR=""   # resolved below

# ── Colours ───────────────────────────────────────────────────────────────────
bold=$(tput bold 2>/dev/null || true)
reset=$(tput sgr0 2>/dev/null || true)
green=$(tput setaf 2 2>/dev/null || true)
yellow=$(tput setaf 3 2>/dev/null || true)
red=$(tput setaf 1 2>/dev/null || true)
blue=$(tput setaf 4 2>/dev/null || true)

step()  { echo "${bold}${blue}==>${reset}${bold} $*${reset}"; }
ok()    { echo "${green}  ✓${reset} $*"; }
warn()  { echo "${yellow}  !${reset} $*"; }
die()   { echo "${red}  ✗${reset} $*" >&2; exit 1; }

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
echo "${bold}◈ Claw Studio${reset} — installer"
echo "────────────────────────────────"
echo ""

# ── macOS check ───────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  die "This installer currently supports macOS only."
fi

# ── Homebrew ──────────────────────────────────────────────────────────────────
step "Checking Homebrew"
if ! command -v brew &>/dev/null; then
  warn "Homebrew not found — installing it now."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for this session (Apple Silicon path)
  [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
else
  ok "Homebrew $(brew --version | head -1)"
fi

# ── Node.js ───────────────────────────────────────────────────────────────────
step "Checking Node.js"
if ! command -v node &>/dev/null; then
  warn "Node.js not found — installing via Homebrew."
  brew install node
else
  NODE_VER=$(node --version | sed 's/v//')
  NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
  if [[ "$NODE_MAJOR" -lt 18 ]]; then
    warn "Node.js $NODE_VER is too old (need 18+) — upgrading."
    brew upgrade node || brew install node
  else
    ok "Node.js v$NODE_VER"
  fi
fi

# ── Git ───────────────────────────────────────────────────────────────────────
step "Checking git"
if ! command -v git &>/dev/null; then
  warn "git not found — installing via Homebrew."
  brew install git
else
  ok "git $(git --version | awk '{print $3}')"
fi

# ── Docker ────────────────────────────────────────────────────────────────────
step "Checking container runtime"
if command -v container &>/dev/null; then
  ok "Apple Container found"
elif command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  ok "Docker found and running"
else
  warn "No container runtime detected."
  echo ""
  echo "  nanoclaw runs agents inside containers. You need either:"
  echo "  • Docker Desktop — https://www.docker.com/products/docker-desktop/"
  echo "  • Apple Container (macOS 26+) — built into the OS"
  echo ""
  echo "  Install Docker Desktop, then re-run this installer."
  echo "  (Or press Enter to continue anyway if you'll set it up separately.)"
  read -r -p "  Continue? [y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 0
fi

# ── nanoclaw ──────────────────────────────────────────────────────────────────
step "Checking nanoclaw"

# Try to find an existing nanoclaw install
found_nanoclaw=""

# 1. Check the default location
if [[ -d "$NANOCLAW_DIR/groups" ]] && [[ -d "$NANOCLAW_DIR/src" || -d "$NANOCLAW_DIR/store" ]]; then
  found_nanoclaw="$NANOCLAW_DIR"
fi

# 2. Check if we're running from inside a nanoclaw dir
if [[ -z "$found_nanoclaw" ]]; then
  check="$PWD"
  for _ in 1 2 3 4 5; do
    if [[ -d "$check/groups" ]] && [[ -d "$check/src" || -d "$check/store" ]]; then
      found_nanoclaw="$check"
      break
    fi
    check="$(dirname "$check")"
  done
fi

if [[ -n "$found_nanoclaw" ]]; then
  ok "Found existing nanoclaw at $found_nanoclaw"
  NANOCLAW_DIR="$found_nanoclaw"
  step "Installing nanoclaw dependencies"
  (cd "$NANOCLAW_DIR" && npm install --silent)
  ok "Dependencies up to date"
else
  warn "nanoclaw not found — cloning to $NANOCLAW_DIR"
  git clone --depth=1 "$NANOCLAW_REPO" "$NANOCLAW_DIR"
  ok "Cloned nanoclaw"
  step "Installing nanoclaw dependencies"
  (cd "$NANOCLAW_DIR" && npm install --silent)
  ok "Dependencies installed"

  # Build the agent container
  step "Building agent container (this takes a minute)"
  if [[ -f "$NANOCLAW_DIR/container/build.sh" ]]; then
    (cd "$NANOCLAW_DIR" && bash container/build.sh)
    ok "Container built"
  else
    warn "container/build.sh not found — skipping container build"
  fi
fi

# ── Claw Studio ───────────────────────────────────────────────────────────────
step "Checking Claw Studio"

PROJECTS_DIR="$NANOCLAW_DIR/Projects"
mkdir -p "$PROJECTS_DIR"
STUDIO_DIR="$PROJECTS_DIR/Claw Studio"

if [[ -d "$STUDIO_DIR/.git" ]]; then
  ok "Claw Studio already installed at $STUDIO_DIR"
  step "Pulling latest updates"
  (cd "$STUDIO_DIR" && git pull --ff-only --quiet)
  ok "Up to date"
else
  git clone --depth=1 "$CLAW_REPO" "$STUDIO_DIR"
  ok "Cloned Claw Studio"
fi

step "Installing Claw Studio dependencies"
(cd "$STUDIO_DIR" && npm install --silent)
ok "Dependencies installed"

# ── launchd service for nanoclaw ──────────────────────────────────────────────
step "Setting up nanoclaw background service"

PLIST_DST="$HOME/Library/LaunchAgents/com.nanoclaw.plist"
PLIST_SRC="$NANOCLAW_DIR/com.nanoclaw.plist"

if [[ ! -f "$PLIST_SRC" ]]; then
  warn "com.nanoclaw.plist not found in nanoclaw directory — skipping service setup"
else
  cp "$PLIST_SRC" "$PLIST_DST"
  # Load (or restart if already loaded)
  launchctl unload "$PLIST_DST" 2>/dev/null || true
  launchctl load "$PLIST_DST"
  ok "nanoclaw service installed and started"
fi

# ── Create launcher script ────────────────────────────────────────────────────
step "Creating launcher"

LAUNCHER="$NANOCLAW_DIR/open-claw-studio.command"
cat > "$LAUNCHER" << LAUNCHEREOF
#!/usr/bin/env bash
# Double-click this file in Finder to open Claw Studio
cd "\$(dirname "\$0")/Projects/Claw Studio"
npm run dev &
SERVER_PID=\$!
sleep 2
# Find the port Vite chose
PORT=\$(lsof -i TCP -sTCP:LISTEN -P -n 2>/dev/null | awk '/node/{print \$9}' | grep -oE '[0-9]+$' | head -1)
open "http://localhost:\${PORT:-5173}"
wait \$SERVER_PID
LAUNCHEREOF
chmod +x "$LAUNCHER"
ok "Launcher created: $LAUNCHER"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────"
echo "${bold}${green}All done!${reset}"
echo ""
echo "  To open Claw Studio:"
echo "  ${bold}cd \"$STUDIO_DIR\" && npm run dev${reset}"
echo ""
echo "  Or double-click: ${bold}open-claw-studio.command${reset} in your nanoclaw folder"
echo ""

# Auto-start if running interactively in a terminal (not piped)
if [[ -t 1 ]]; then
  read -r -p "  Start Claw Studio now? [Y/n] " yn
  yn="${yn:-y}"
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    cd "$STUDIO_DIR"
    npm run dev &
    sleep 2
    PORT=$(lsof -i TCP -sTCP:LISTEN -P -n 2>/dev/null | awk '/node/{print $9}' | grep -oE '[0-9]+$' | head -1)
    open "http://localhost:${PORT:-5173}"
    echo "  Claw Studio is running. Close this window to stop it."
    wait
  fi
fi
