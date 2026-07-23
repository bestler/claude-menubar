#!/usr/bin/env bash
# Build a release binary and assemble a menu-bar-only .app bundle,
# ad-hoc signed so launch-at-login (SMAppService) works locally.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Claude Menubar"
BUNDLE="build/${APP_NAME}.app"
BIN_NAME="ClaudeMenubar"

echo "==> swift build -c release"
swift build -c release

echo "==> Assembling ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp ".build/release/${BIN_NAME}" "${BUNDLE}/Contents/MacOS/${BIN_NAME}"
cp "Resources/Info.plist" "${BUNDLE}/Contents/Info.plist"
[ -f "Resources/AppIcon.icns" ] && cp "Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns" || true

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$BUNDLE"

echo ""
echo "Built: ${BUNDLE}"
echo "Install with:"
echo "  mv \"${BUNDLE}\" /Applications/"
echo "  open \"/Applications/${APP_NAME}.app\""
echo ""
echo "Then use the menu-bar 'Launch at login' toggle (requires the app to live in /Applications)."
