#!/bin/bash
# Development runner for Extremis
# Creates a minimal .app bundle from the debug build so TCC (microphone, speech)
# permissions work correctly. Runs the binary directly so logs appear in terminal.
#
# Usage: ./scripts/run-dev.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Extremis"
DEV_BUNDLE="$PROJECT_DIR/.build/dev/${APP_NAME}.app"

cd "$PROJECT_DIR"

# Build debug
echo "Building debug..."
swift build 2>&1

# Create minimal .app bundle
rm -rf "$DEV_BUNDLE"
mkdir -p "$DEV_BUNDLE/Contents/MacOS"

# Copy binary
cp ".build/debug/Extremis" "$DEV_BUNDLE/Contents/MacOS/"

# Copy Info.plist (required for TCC privacy permissions)
cp "Info.plist" "$DEV_BUNDLE/Contents/"

# Copy SPM resource bundle into Contents/Resources (must be sealed inside the bundle
# for codesign to succeed — placing at bundle root causes "unsealed contents" error)
RESOURCE_BUNDLE=".build/debug/Extremis_Extremis.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    mkdir -p "$DEV_BUNDLE/Contents/Resources"
    cp -r "$RESOURCE_BUNDLE" "$DEV_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPL????" > "$DEV_BUNDLE/Contents/PkgInfo"

# Ad-hoc code sign the full .app bundle so TCC can bind Info.plist and resolve the
# bundle identifier (com.extremis.app). Required on macOS 26+ for privacy permission prompts.
# Use a dev-specific entitlements plist without keychain-access-groups (the production
# entitlements contain $(AppIdentifierPrefix), an unresolved Xcode variable that
# causes SIGKILL on ad-hoc signed binaries).
DEV_ENTITLEMENTS="$PROJECT_DIR/.build/dev-entitlements.plist"
/usr/libexec/PlistBuddy -c "Clear dict" "$DEV_ENTITLEMENTS" 2>/dev/null || plutil -create xml1 "$DEV_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.app-sandbox bool false" "$DEV_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.automation.apple-events bool true" "$DEV_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" "$DEV_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.device.audio-input bool true" "$DEV_ENTITLEMENTS"

echo "Signing (ad-hoc, hardened runtime)..."
codesign --force --sign - --options runtime --identifier "com.extremis.app" --entitlements "$DEV_ENTITLEMENTS" "$DEV_BUNDLE"

echo "Launching with logs..."
echo "=========================================="
echo "Logs stream below. Press Ctrl+C to stop (also quits Extremis)."
echo ""

# Launch via `open` so the app gets its own process coalition.
# macOS 26 TCC checks the coalition for privacy keys — running via `exec` from a terminal
# inherits the terminal's coalition (e.g., VSCode), causing TCC crashes for microphone/speech.
open "$DEV_BUNDLE"

# Give the app a moment to start, then stream its logs.
sleep 1
LOG_PID=$(pgrep -n -x Extremis)

# On Ctrl+C, also quit the app
cleanup() {
    if [ -n "$LOG_PID" ]; then
        kill "$LOG_PID" 2>/dev/null
    fi
    exit 0
}
trap cleanup INT TERM

if [ -n "$LOG_PID" ]; then
    log stream --process "$LOG_PID" --style compact 2>/dev/null
else
    echo "Warning: Could not find Extremis process for log streaming."
    echo "Check Console.app for logs, or run: log stream --process Extremis"
    wait
fi
