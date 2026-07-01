#!/usr/bin/env bash
# Rebuilds the DevTools extension and deploys it into the runtime package that
# ships it (packages/flutter_leak_radar/extension/devtools/build/).
#
# Uses the canvaskit CDN (loaded from gstatic at runtime) rather than bundling
# it, keeping the committed/published build small (~6 MB vs ~34 MB). The
# extension therefore needs network access the first time it renders in
# DevTools — which is the normal case.
#
# Run this whenever packages/flutter_leak_radar_devtools changes, and before
# publishing flutter_leak_radar. Commit the resulting build/ directory.
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="packages/flutter_leak_radar_devtools"
DEST="packages/flutter_leak_radar/extension/devtools/build"

echo ">> Building $SRC for web (canvaskit via CDN, no service worker)..."
( cd "$SRC" && flutter build web --web-resources-cdn --pwa-strategy=none )

# The runtime loads canvaskit from the CDN, so the bundled local copy is an
# unused ~26 MB fallback — drop it, along with debug .symbols files.
rm -rf "$SRC/build/web/canvaskit"
find "$SRC/build/web" -name "*.symbols" -delete 2>/dev/null || true

echo ">> Deploying to $DEST ..."
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC/build/web/." "$DEST/"

echo ">> Done — $(du -sh "$DEST" | cut -f1) at $DEST"
