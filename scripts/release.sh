#!/usr/bin/env bash
# Cuts a signed, notarized release.
#
#   ./scripts/release.sh 1.0.1
#
# Runs the tests, bumps the version, builds and notarizes the DMG, commits, tags,
# pushes, and publishes the GitHub release with the DMG attached. Release notes
# come from NOTES_FILE when set, and are generated from the commits otherwise.
#
# It refuses to run rather than ship something subtly broken: without a Developer
# ID signature, downloads hit a Gatekeeper wall and keyboard sounds lose their
# permission on every update.
set -euo pipefail

VERSION="${1:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
PLIST="Resources/Info.plist"
DMG="build/Textur.dmg"

die() { echo "error: $*" >&2; exit 1; }

cd "$(dirname "$0")/.."

[ -n "$VERSION" ] || die "usage: ./scripts/release.sh <version>   e.g. 1.0.1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3, got '$VERSION'"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "releases are cut from main"
[ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit or stash first"
git fetch origin main --quiet
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "local main differs from origin/main; push or pull first"
! git rev-parse "v$VERSION" >/dev/null 2>&1 || die "tag v$VERSION already exists"
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
[ "$CURRENT" != "$VERSION" ] || die "$PLIST is already at $VERSION"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application" \
    || die "no Developer ID Application identity in the keychain"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notarization profile '$NOTARY_PROFILE' not found; create it with: xcrun notarytool store-credentials $NOTARY_PROFILE"
[ -z "${NOTES_FILE:-}" ] || [ -f "$NOTES_FILE" ] || die "NOTES_FILE '$NOTES_FILE' not found"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

echo "About to release v$VERSION (currently $CURRENT)."
read -r -p "Continue? [y/N] " reply || true
[[ "${reply:-}" =~ ^[Yy]$ ]] || die "aborted"

echo "==> Running tests…"
swift test

echo "==> Bumping $PLIST to ${VERSION}…"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"

NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/build-dmg.sh
spctl --assess --type open --context context:primary-signature -v "$DMG" \
    || die "Gatekeeper rejected $DMG; refusing to publish"

echo "==> Committing, tagging and pushing…"
git add "$PLIST"
git commit -m "chore: release v$VERSION"
git tag -a "v$VERSION" -m "v$VERSION"
git push origin main
git push origin "v$VERSION"

echo "==> Publishing the GitHub release…"
if [ -n "${NOTES_FILE:-}" ]; then
    NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
    NOTES_ARGS=(--generate-notes)
fi
RELEASE_ARGS=("v$VERSION" "$DMG" --title "Textur $VERSION" "${NOTES_ARGS[@]}")
# The tag is already pushed, so a failure here only needs this one command re-run.
gh release create "${RELEASE_ARGS[@]}" \
    || die "v$VERSION is tagged and pushed but not published. Finish with: gh release create $(printf '%q ' "${RELEASE_ARGS[@]}")"
echo "Released: $(gh release view "v$VERSION" --json url -q .url)"
