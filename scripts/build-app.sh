#!/usr/bin/env bash
# Builds build/HapticPad.app, universal (Apple silicon and Intel).
#
#   ./scripts/build-app.sh             build the app
#   ./scripts/build-app.sh --install   build it and copy it to /Applications
#
# Signs with the keychain's Developer ID Application identity when there is one,
# and falls back to ad-hoc signing otherwise (CI runners, contributors). Set
# SIGN_IDENTITY to pick an identity, or SIGN_IDENTITY=- to force ad-hoc.
#
# Why the identity matters: macOS keys the Input Monitoring permission to the
# app's code identity. An ad-hoc signature has none that survives a rebuild, so
# keyboard sounds need the permission again after every build.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/HapticPad.app"
ARCHS=(--arch arm64 --arch x86_64)

if [ -z "${SIGN_IDENTITY+set}" ]; then
    CANDIDATES=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | sed -E 's/.*"(.*)".*/\1/' || true)
    if [ "$(printf '%s' "$CANDIDATES" | grep -c . || true)" -gt 1 ]; then
        echo "error: several Developer ID Application identities; set SIGN_IDENTITY to one of:" >&2
        printf '%s\n' "$CANDIDATES" | sed 's/^/  /' >&2
        exit 1
    fi
    SIGN_IDENTITY="${CANDIDATES:--}"
fi

echo "==> Building (release, universal)…"
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

echo "==> Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HapticPad" "$APP/Contents/MacOS/HapticPad"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# --options runtime and --timestamp are both required for notarization.
if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "==> Signing with: $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    echo "==> No Developer ID identity: signing ad-hoc."
    codesign --force --options runtime --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "==> Built $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x HapticPad 2>/dev/null || true
    rm -rf /Applications/HapticPad.app
    cp -R "$APP" /Applications/
    echo "==> Installed /Applications/HapticPad.app"
fi
