#!/bin/bash
# Build script for Extremis
# Creates .app bundle and ZIP for distribution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Extremis"
BUILD_DIR="$PROJECT_DIR/build"
DMG_WIDTH=600
DMG_HEIGHT=400

echo "🔨 Building Extremis..."

cd "$PROJECT_DIR"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release binary
swift build -c release

# Create app bundle structure
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp ".build/release/Extremis" "$APP_BUNDLE/Contents/MacOS/"

# Copy SPM resource bundle (contains models.json and prompt templates)
# SPM generates this bundle with name: {PackageName}_{TargetName}.bundle
# IMPORTANT: Bundle.module looks for it at Bundle.main.bundleURL (the .app root), NOT Contents/Resources
RESOURCE_BUNDLE=".build/release/Extremis_Extremis.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    echo "📦 Copying resource bundle..."
    cp -r "$RESOURCE_BUNDLE" "$APP_BUNDLE/"
else
    echo "⚠️  Warning: Resource bundle not found at $RESOURCE_BUNDLE"
    echo "   The app may crash on startup without resources."
fi

# Copy Info.plist and stamp version from latest git tag
cp "Info.plist" "$APP_BUNDLE/Contents/"
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -n "$GIT_TAG" ]; then
    BUILD_VERSION="${GIT_TAG#v}"
    echo "📌 Stamping version $BUILD_VERSION (from tag $GIT_TAG)"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BUILD_VERSION" "$APP_BUNDLE/Contents/Info.plist"
fi

# Copy entitlements (for reference, not embedded in unsigned app)
cp "Extremis.entitlements" "$BUILD_DIR/"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Process and copy app icon if exists
if [ -d "Resources/Assets.xcassets/AppIcon.appiconset" ]; then
    echo "📦 Processing app icon..."
    ICON_SRC=$(find "Resources/Assets.xcassets/AppIcon.appiconset" -name "*.png" | head -1)
    if [ -n "$ICON_SRC" ]; then
        cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
    fi
fi

echo "✅ Created $APP_BUNDLE"

# Create ZIP for easy sharing
echo "📦 Creating ZIP..."
cd "$BUILD_DIR"
zip -r -q "$APP_NAME.zip" "$APP_NAME.app"
echo "✅ Created $BUILD_DIR/$APP_NAME.zip"

# Create styled DMG using create-dmg if available, otherwise basic DMG
if command -v hdiutil &> /dev/null; then
    echo "💿 Creating DMG..."

    DMG_TEMP="$BUILD_DIR/dmg_temp"
    DMG_FINAL="$BUILD_DIR/$APP_NAME.dmg"

    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"
    cp -r "$APP_BUNDLE" "$DMG_TEMP/"
    ln -s /Applications "$DMG_TEMP/Applications"

    # Check if create-dmg is available and Finder automation is permitted
    if command -v create-dmg &> /dev/null; then
        echo "📐 Using create-dmg for styled installer..."
        rm -f "$DMG_FINAL"

        # Try create-dmg, fall back to basic if it fails (e.g., no Finder permission)
        if create-dmg \
            --volname "$APP_NAME" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "$APP_NAME.app" 450 185 \
            --icon "Applications" 150 185 \
            --hide-extension "$APP_NAME.app" \
            --app-drop-link 150 185 \
            --no-internet-enable \
            "$DMG_FINAL" \
            "$APP_BUNDLE" 2>/dev/null; then
            echo "✅ Styled DMG created"
        else
            echo "⚠️  create-dmg styling failed (grant Finder permission in System Settings → Privacy → Automation)"
            echo "   Creating basic DMG instead..."
            hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_FINAL"
        fi
    else
        echo "💡 Tip: Install 'create-dmg' for a prettier installer:"
        echo "   brew install create-dmg"
        echo ""
        hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_FINAL"
    fi

    rm -rf "$DMG_TEMP"
    echo "✅ Created $DMG_FINAL"
fi

echo ""
echo "=========================================="
echo "📍 Build outputs in: $BUILD_DIR"
echo "=========================================="
echo "  • $APP_NAME.app  - The application"
echo "  • $APP_NAME.zip  - ZIP for sharing"
if [ -f "$BUILD_DIR/$APP_NAME.dmg" ]; then
echo "  • $APP_NAME.dmg  - DMG installer (styled)"
fi
echo ""
echo "⚠️  Note: App is unsigned. Recipients need to:"
echo "   Right-click → Open → Open (to bypass Gatekeeper)"
echo "=========================================="

