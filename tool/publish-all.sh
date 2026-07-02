#!/usr/bin/env bash
#
# Publishes the flutter-leak-radar packages to pub.dev in dependency-tier order,
# waiting for each tier to become visible on pub.dev before the next (a
# dependent's resolution FAILS until its dependencies are actually live).
#
# Wraps tool/publish.sh (which strips `resolution: workspace` for the publish and
# targets pub.dev even behind a private PUB_HOSTED_URL mirror).
#
# Before a release, run tool/sync-constraints.sh so the upper tiers REQUIRE the
# latest lower tiers, and bump/republish any package whose constraints changed.
#
# Usage:
#   tool/publish-all.sh --dry-run          # validate packaging for all tiers
#   tool/publish-all.sh                     # real publish, interactive confirm per package
#   tool/publish-all.sh --force             # real publish, non-interactive (CI / OIDC)
#   tool/publish-all.sh --tier 0            # publish only a single tier (0 = core)
#   tool/publish-all.sh --tier 2 --force    # e.g. re-publish just the umbrella
#
# Preconditions:
#   - On `main`, tree clean, changes committed.
#   - Authenticated to pub.dev (`dart pub login`) with publish rights, stable channel.
#   - The bundled DevTools extension is current (tool/build_devtools_extension.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { echo "usage: tool/publish-all.sh [--tier 0|1|2] [--dry-run|--force]"; }

TIER=""
MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tier=*) TIER="${1#--tier=}" ;;
    --tier)   TIER="${2:-}"; shift ;;
    --dry-run|--force) MODE="$1" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
  shift
done

# Dependency tiers — each tier needs the previous one live on pub.dev.
TIER0=(radar_ui radar_trace leak_graph)          # core, no intra-repo deps
TIER1=(flutter_leak_radar flutter_perf_radar)    # standalone radars → need tier 0
TIER2=(radarscope)                               # umbrella → needs tier 1
# Independent island (own cadence, not tiered): flutter_leak_radar_lint.
# Never published: flutter_leak_radar_devtools (publish_to: none).

tier_pkgs() {
  case "$1" in
    0) printf '%s\n' "${TIER0[@]}" ;;
    1) printf '%s\n' "${TIER1[@]}" ;;
    2) printf '%s\n' "${TIER2[@]}" ;;
    *) echo "unknown tier: $1 (use 0, 1, or 2)" >&2; exit 64 ;;
  esac
}

pkg_version() { grep -m1 '^version:' "packages/$1/pubspec.yaml" | awk '{print $2}'; }

publish_pkg() {
  local pkg="$1"
  echo
  echo "==== $pkg $(pkg_version "$pkg") ===="
  if [ "$MODE" = "--dry-run" ]; then
    # A dry-run always ends with one benign warning (publish.sh strips
    # `resolution: workspace`, which the git tree then reports as a modified
    # pubspec) and `dart pub publish --dry-run` exits non-zero on any warning —
    # tolerate it so every package is validated. Review the output for any
    # warning beyond that one.
    tool/publish.sh "packages/$pkg" --dry-run || true
  else
    # $MODE is "" (interactive) or --force; intentionally unquoted so empty
    # expands to no argument.
    tool/publish.sh "packages/$pkg" $MODE
  fi
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

publish_tier() {
  local n="$1"
  echo
  echo ">>>> Tier $n"
  for p in $(tier_pkgs "$n"); do publish_pkg "$p"; done
}

wait_tier() {
  local n="$1"
  for p in $(tier_pkgs "$n"); do wait_for_pubdev "$p"; done
}

# Which tiers to process: a single --tier N, else all in order.
if [ -n "$TIER" ]; then
  TIERS=("$TIER")
else
  TIERS=(0 1 2)
fi

if [ "$MODE" = "--dry-run" ]; then
  for n in "${TIERS[@]}"; do publish_tier "$n"; done
  echo
  echo ">> Dry-run complete. NOTE: a tier only resolves for dry-run once every"
  echo ">> tier below it is live on pub.dev, so higher-tier 'could not resolve'"
  echo ">> warnings are expected until you publish for real."
  exit 0
fi

# Real publish: publish each tier, then wait for it before the next.
for n in "${TIERS[@]}"; do
  publish_tier "$n"
  wait_tier "$n"
done

echo
echo ">> Done: tier(s) ${TIERS[*]}."
echo ">> Independent (own cadence): flutter_leak_radar_lint."
echo ">> Not published: flutter_leak_radar_devtools (publish_to: none)."
echo ">> First-time publishes need automated publishing enabled on pub.dev"
echo ">> (Admin → Automated publishing) per docs/PUBLISHING.md."
