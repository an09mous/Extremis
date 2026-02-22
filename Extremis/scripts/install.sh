#!/bin/bash
# Extremis Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/an09mous/Extremis/main/Extremis/scripts/install.sh | bash
set -euo pipefail

APP_NAME="Extremis"
INSTALL_DIR="/Applications"
REPO="an09mous/Extremis"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BOLD}$1${NC}"; }
warn()  { echo -e "${YELLOW}$1${NC}"; }
error() { echo -e "${RED}$1${NC}" >&2; }
ok()    { echo -e "${GREEN}$1${NC}"; }

# --- Check macOS ---
if [ "$(uname -s)" != "Darwin" ]; then
    error "Error: Extremis is a macOS app. This installer only works on macOS."
    exit 1
fi

MACOS_VERSION=$(sw_vers -productVersion)
MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [ "$MAJOR" -lt 13 ]; then
    error "Error: Extremis requires macOS 13.0 (Ventura) or later. You have $MACOS_VERSION."
    exit 1
fi

# --- Check architecture ---
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    warn "Note: Extremis is built for Apple Silicon. It may run via Rosetta 2 on Intel Macs."
fi

# --- Fetch latest release ---
info "Fetching latest release..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null) || {
    error "Error: Could not fetch release info. Check https://github.com/$REPO/releases"
    exit 1
}

TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4 || true)
# Normalize: strip 'v' prefix so versions always match Info.plist format (e.g., "1.0.0")
VERSION="${TAG#v}"

if [ -z "$DOWNLOAD_URL" ]; then
    error "Error: No ZIP found in release ${VERSION:-unknown}."
    error "       Check https://github.com/$REPO/releases"
    exit 1
fi

# --- Check if already up to date ---
CURRENT_VERSION=""
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    CURRENT_VERSION=$(defaults read "$INSTALL_DIR/$APP_NAME.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
    if [ "$CURRENT_VERSION" = "$VERSION" ]; then
        ok "Extremis $VERSION is already up to date."
        exit 0
    fi
fi

info "Installing Extremis $VERSION..."

# --- Download and extract ---
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading..."
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME.zip"

echo "Extracting..."
ditto -xk "$TMP_DIR/$APP_NAME.zip" "$TMP_DIR"

# Verify extraction
if [ ! -d "$TMP_DIR/$APP_NAME.app" ]; then
    error "Error: $APP_NAME.app not found after extraction."
    exit 1
fi

# --- Quit running instance ---
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    warn "Extremis is running. Quitting it first..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
fi

# --- Install ---
IS_UPDATE=false
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    IS_UPDATE=true
    echo "Updating from ${CURRENT_VERSION:-unknown}..."
    mv "$INSTALL_DIR/$APP_NAME.app" "$TMP_DIR/$APP_NAME.app.bak"
fi

echo "Installing to $INSTALL_DIR..."
if ! mv "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/" 2>/dev/null; then
    warn "Permission denied for /Applications. Trying with sudo..."
    if ! sudo mv "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"; then
        # Restore backup if install failed
        if [ -d "$TMP_DIR/$APP_NAME.app.bak" ]; then
            warn "Install failed. Restoring previous version..."
            mv "$TMP_DIR/$APP_NAME.app.bak" "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || \
                sudo mv "$TMP_DIR/$APP_NAME.app.bak" "$INSTALL_DIR/$APP_NAME.app"
        fi
        error "Error: Could not install to $INSTALL_DIR."
        exit 1
    fi
fi

# --- Done ---
echo ""
if [ "$IS_UPDATE" = true ] && [ -n "$CURRENT_VERSION" ]; then
    ok "Extremis updated: $CURRENT_VERSION → $VERSION"
else
    ok "Extremis $VERSION installed successfully!"
fi
echo ""
if [ "$IS_UPDATE" = true ]; then
    # Unsigned app binary hash changed — old TCC entry is stale
    echo "Resetting Accessibility permission (binary changed)..."
    tccutil reset Accessibility com.extremis.app 2>/dev/null || true
    echo ""
    warn "Action required: Re-add Accessibility permission."
    echo "  1. Open System Settings → Privacy & Security → Accessibility"
    echo "  2. Remove Extremis from the list"
    echo "  3. Re-add Extremis and enable it"
    echo "  4. Restart Extremis"
else
    info "First launch setup:"
    echo "  1. Open Extremis from Applications or Spotlight"
    echo "  2. Grant Accessibility permission in System Settings"
    echo "  3. Configure an LLM provider in Preferences (menu bar icon)"
    echo ""
    echo "  Hotkeys:  Option+Space (Quick/Chat)  |  Option+Tab (Summarize)"
fi
echo ""
