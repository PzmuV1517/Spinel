#!/bin/bash
# Builds build/Spinel.app. Signing with a stable identity (any "Apple Development" or
# "Developer ID" certificate) matters: macOS ties the Accessibility grant to the signature,
# so an ad-hoc signed build has to be re-approved after every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION=${CONFIGURATION:-release}
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/Spinel"

APP=build/Spinel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Spinel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')}
if [ -z "$IDENTITY" ]; then
    echo "warning: no signing identity found, signing ad-hoc (Accessibility must be re-granted after each build)" >&2
    IDENTITY=-
fi
codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: $IDENTITY)"
