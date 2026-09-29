#!/usr/bin/env bash
# Builds build/HapticPad.dmg: the app next to an Applications link, ready to drag.
#
#   NOTARY_PROFILE=<profile> ./scripts/build-dmg.sh
#
# With NOTARY_PROFILE, the app and the disk image are notarized and stapled. The
# profile is a notarytool keychain entry, created once on your Mac with
#   xcrun notarytool store-credentials <profile> --apple-id … --team-id … --password …
# It never leaves the keychain. Without it, the DMG is built but not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/HapticPad.app"
DMG="build/HapticPad.dmg"
STAGE="build/dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

die() { echo "error: $*" >&2; exit 1; }

./scripts/build-app.sh
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)$/\1/p' | head -1)

notarize() {
    echo "==> Notarizing $1 (this waits on Apple, usually a few minutes)…"
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

# Staple the app itself too: a ticket only on the DMG leaves the app ticketless
# once it is dragged to Applications, and Gatekeeper then has to ask Apple online.
if [ -n "$NOTARY_PROFILE" ]; then
    [ -n "$IDENTITY" ] || die "notarization needs a Developer ID signature"
    ZIP="build/HapticPad-notarize.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    rm -f "$ZIP"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
fi

echo "==> Creating ${DMG}…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "HapticPad" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# The disk image needs its own signature, applied before it is notarized.
if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

if [ -n "$NOTARY_PROFILE" ]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    echo "==> Gatekeeper verdict (what a downloader gets):"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
else
    echo "==> Not notarized (NOTARY_PROFILE unset)."
fi
echo "==> Done: $DMG"
