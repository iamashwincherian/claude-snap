#!/bin/bash
set -e

# ClaudeSnap installer — downloads and installs the latest release to /Applications

REPO="iamashwincherian/claude-snap"
INSTALL_DIR="/Applications"

echo "ClaudeSnap Installer"
echo "===================="

# Fetch latest release
echo "Fetching latest release..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | grep -o '"browser_download_url": "[^"]*\.zip"' | head -1 | cut -d'"' -f4)
VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Error: No releases found for $REPO"
  echo ""
  echo "To build from source:"
  echo "  1. Clone: git clone https://github.com/$REPO.git"
  echo "  2. Build: cd claude-snap && xcodebuild build -scheme ClaudeSnap -configuration Release"
  echo "  3. Copy: cp -r /path/to/DerivedData/ClaudeSnap-*/Build/Products/Release/ClaudeSnap.app /Applications/"
  exit 1
fi

echo "Found version: $VERSION"
echo "Downloading from: $DOWNLOAD_URL"

# Download to temp
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

curl -L -o "$TEMP_DIR/ClaudeSnap.zip" "$DOWNLOAD_URL"
unzip -q "$TEMP_DIR/ClaudeSnap.zip" -d "$TEMP_DIR"

# Find the .app (in case it's nested)
APP_PATH=$(find "$TEMP_DIR" -name "ClaudeSnap.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
  echo "Error: ClaudeSnap.app not found in release"
  exit 1
fi

# Remove old version if it exists
if [ -d "$INSTALL_DIR/ClaudeSnap.app" ]; then
  echo "Removing existing installation..."
  rm -rf "$INSTALL_DIR/ClaudeSnap.app"
fi

# Install
echo "Installing to $INSTALL_DIR..."
cp -r "$APP_PATH" "$INSTALL_DIR/"

# ClaudeSnap isn't notarized (no paid Apple Developer account), so Gatekeeper blocks the
# quarantine flag curl/unzip leaves behind with a misleading "damaged" error. Strip it —
# this script downloaded straight from the GitHub release, so the app is what it claims to be.
xattr -cr "$INSTALL_DIR/ClaudeSnap.app"

# Update Finder/Dock icon cache
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true

echo "✓ ClaudeSnap $VERSION installed successfully"
echo ""
echo "Launch it from /Applications or open it with: open /Applications/ClaudeSnap.app"
