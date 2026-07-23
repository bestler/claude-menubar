#!/usr/bin/env bash
# Build a release binary and assemble a menu-bar-only .app bundle.
#
# Signing:
#   - If a "Developer ID Application" cert is present (or CODESIGN_IDENTITY is
#     set), signs with the hardened runtime + secure timestamp so the app can
#     be notarized (see scripts/release.sh).
#   - Otherwise falls back to ad-hoc signing (fine for local dev only).
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

# Pick a signing identity: explicit override, else first Developer ID Application.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | awk -F'"' '/Developer ID Application/{print $2; exit}')}"

if [ -n "$IDENTITY" ]; then
  echo "==> Signing with Developer ID (hardened runtime): $IDENTITY"
  codesign --force --options runtime --timestamp \
           --sign "$IDENTITY" "${BUNDLE}/Contents/MacOS/${BIN_NAME}"
  codesign --force --options runtime --timestamp \
           --sign "$IDENTITY" "$BUNDLE"
  codesign --verify --strict --verbose=2 "$BUNDLE"
else
  echo "==> No Developer ID cert found — ad-hoc signing (local/dev only)"
  echo "    (Create a Developer ID Application cert to produce a notarizable build.)"
  codesign --force --deep --sign - "$BUNDLE"
fi

echo ""
echo "Built: ${BUNDLE}"
echo "Install locally with:"
echo "  mv \"${BUNDLE}\" /Applications/ && open \"/Applications/${APP_NAME}.app\""
