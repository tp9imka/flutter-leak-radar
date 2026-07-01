#!/usr/bin/env bash
#
# Publishes the flutter-leak-radar packages changed in a release round to
# pub.dev, in dependency-tier order, waiting for each tier to become visible on
# pub.dev before publishing the next (a dependent's resolution FAILS until its
# dependencies are actually live).
#
# Wraps tool/publish.sh (which strips `resolution: workspace` for the publish
# and targets pub.dev even behind a private PUB_HOSTED_URL mirror).
#
# Usage:
#   tool/publish-all.sh --dry-run   # validate tier 0 packaging (0 warnings)
#   tool/publish-all.sh             # real publish, interactive confirm per package
#   tool/publish-all.sh --force     # real publish, non-interactive (CI / OIDC)
#
# Preconditions:
#   - On `main`, tree clean, changes committed.
#   - Authenticated to pub.dev (`dart pub login`) with publish rights on these
#     packages, on the stable channel.
#   - The bundled DevTools extension is current
#     (tool/build_devtools_extension.sh) — it ships inside flutter_leak_radar.
#
# Tiers (edit the arrays each round to match what actually changed):
#   Tier 0 — no sibling deps:            radar_ui, radar_trace, leak_graph
#   Tier 1 — need tier 0 live on pub.dev: flutter_leak_radar, flutter_perf_radar
#   Skipped this round (unchanged): radarscope (umbrella; its `^` constraints
#     pick up the new tier-0/1 versions automatically), flutter_leak_radar_lint,
#     flutter_leak_radar_devtools (publish_to: none).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"
case "$MODE" in
  ""|--dry-run|--force) ;;
  *) echo "usage: tool/publish-all.sh [--dry-run|--force]" >&2; exit 64 ;;
esac

TIER0=(radar_ui radar_trace leak_graph)
TIER1=(flutter_leak_radar flutter_perf_radar)

pkg_version() { grep -m1 '^version:' "packages/$1/pubspec.yaml" | awk '{print $2}'; }

publish_pkg() {
  local pkg="$1"
  echo
  echo "==== $pkg $(pkg_version "$pkg") ===="
  tool/publish.sh "packages/$pkg" $MODE
}

# Poll pub.dev until <pkg>'s current pubspec version is an available version.
wait_for_pubdev() {
  local pkg="$1" ver
  ver="$(pkg_version "$pkg")"
  echo ">> Waiting for $pkg $ver to be live on pub.dev..."
  for _ in $(seq 1 60); do
    if curl -fsSL "https://pub.dev/api/packages/$pkg" 2>/dev/null \
         | tr ',' '\n' | grep -q "\"version\":\"$ver\""; then
      echo ">> $pkg $ver is live."
      return 0
    fi
    sleep 10
  done
  echo "!! Timed out waiting for $pkg $ver on pub.dev" >&2
  return 1
}

if [ "$MODE" = "--dry-run" ]; then
  # Only tier 0 can be dry-run standalone: a tier-1 dry-run cannot resolve until
  # tier 0 is actually published. Validate tier 0 here.
  #
  # A dry-run always ends with one benign warning — publish.sh strips
  # `resolution: workspace`, which the git tree then reports as a modified
  # pubspec.yaml — and `dart pub publish --dry-run` exits non-zero on any
  # warning. Tolerate it so every tier-0 package is validated; review the
  # per-package output for any warning beyond that expected one.
  for p in "${TIER0[@]}"; do publish_pkg "$p" || true; done
  echo
  echo ">> Tier 0 dry-run complete. Tier 1 (flutter_leak_radar, flutter_perf_radar)"
  echo ">> only resolves for dry-run once tier 0 is live on pub.dev."
  exit 0
fi

echo ">> Publishing tier 0..."
for p in "${TIER0[@]}"; do publish_pkg "$p"; done
for p in "${TIER0[@]}"; do wait_for_pubdev "$p"; done

echo ">> Publishing tier 1..."
for p in "${TIER1[@]}"; do publish_pkg "$p"; done

echo
echo ">> Done. Published: ${TIER0[*]} ${TIER1[*]}."
echo ">> Skipped (unchanged): radarscope, flutter_leak_radar_lint, flutter_leak_radar_devtools."
echo ">> For any FIRST-time publish, enable automated publishing on pub.dev"
echo ">> (Admin → Automated publishing) per docs/PUBLISHING.md, then release via tags."
