#!/usr/bin/env bash
# quietshrink installer
# Usage: curl -fsSL https://raw.githubusercontent.com/achiya-automation/quietshrink/main/install.sh | bash

set -euo pipefail

REPO_URL="https://github.com/achiya-automation/quietshrink.git"
INSTALL_DIR="${QUIETSHRINK_INSTALL_DIR:-$HOME/.quietshrink}"
BIN_TARGET="${QUIETSHRINK_BIN:-/usr/local/bin/quietshrink}"

C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_BLUE=$'\033[34m'
C_BOLD=$'\033[1m'
C_RESET=$'\033[0m'

echo
echo "${C_BOLD}quietshrink installer${C_RESET}"
echo

# Check macOS
if [ "$(uname -s)" != "Darwin" ]; then
  echo "${C_YELLOW}⚠${C_RESET}  quietshrink is optimized for macOS. Other platforms work but without hardware acceleration."
fi

# Check ffmpeg
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "${C_RED}✗${C_RESET} ffmpeg not found."
  if command -v brew >/dev/null 2>&1; then
    echo "  Installing via Homebrew..."
    brew install ffmpeg
  else
    echo "  Please install ffmpeg first: ${C_BLUE}https://ffmpeg.org/download.html${C_RESET}"
    exit 1
  fi
fi

# Check ffmpeg has videotoolbox
if ! ffmpeg -hide_banner -encoders 2>&1 | grep -q "hevc_videotoolbox"; then
  echo "${C_YELLOW}⚠${C_RESET}  Your ffmpeg lacks hevc_videotoolbox. Reinstall with: ${C_BLUE}brew reinstall ffmpeg${C_RESET}"
fi

# Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "${C_BLUE}●${C_RESET} Updating existing install at ${INSTALL_DIR}..."
  git -C "$INSTALL_DIR" pull --quiet
else
  echo "${C_BLUE}●${C_RESET} Cloning to ${INSTALL_DIR}..."
  git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/bin/quietshrink"

# Symlink
if [ -L "$BIN_TARGET" ] || [ -f "$BIN_TARGET" ]; then
  if [ -w "$(dirname "$BIN_TARGET")" ]; then
    rm -f "$BIN_TARGET"
  else
    sudo rm -f "$BIN_TARGET"
  fi
fi

if [ -w "$(dirname "$BIN_TARGET")" ]; then
  ln -s "$INSTALL_DIR/bin/quietshrink" "$BIN_TARGET"
else
  echo "${C_BLUE}●${C_RESET} Need sudo to symlink to $BIN_TARGET"
  sudo ln -s "$INSTALL_DIR/bin/quietshrink" "$BIN_TARGET"
fi

echo
echo "${C_GREEN}✓${C_RESET} quietshrink installed to $BIN_TARGET"
echo
echo "  Try it:"
echo "    ${C_BOLD}quietshrink ~/Desktop/some-recording.mov${C_RESET}"
echo
