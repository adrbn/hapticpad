#!/usr/bin/env bash
# Renders the README images into docs/assets: the hero (light and dark) and the icon.
#
# The panel is rendered with the default settings and the default blue accent, so
# the images look the same whoever runs this.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
# Launched through LaunchServices, so the panel draws as it does when opened.
open -W -n build/Textur.app --args --snapshot "$PWD/docs/assets" -AppleAccentColor 4
sips -s format png Resources/AppIcon.icns --resampleWidth 256 --out docs/assets/icon.png >/dev/null
echo "==> Updated docs/assets"
