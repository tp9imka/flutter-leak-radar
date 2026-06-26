#!/usr/bin/env bash
#
# Publish a workspace member to pub.dev with a clean, standalone pubspec.
#
# The repo uses a pub `workspace:` so the flutter_leak_radar_lint tests can
# resolve Flutter (custom_lint analyses Flutter-importing fixtures against the
# shared workspace package config). But a published member keeps
# `resolution: workspace`, which pub.dev's pana CANNOT resolve standalone —
# it fails `dart pub get`, so the package gets "incomplete analysis" and 0/50
# static + 0/20 platform. This helper strips the workspace bits for the publish
# only, then restores them.
#
# Usage:
#   tool/publish.sh packages/leak_graph            # real publish
#   tool/publish.sh packages/leak_graph --dry-run  # validate only
#
# Release ORDER: leak_graph BEFORE flutter_leak_radar (the latter depends on
# leak_graph: ^0.1.0, which must already be on pub.dev).
set -euo pipefail

PKG="${1:?usage: tool/publish.sh <package-dir> [--dry-run]}"
DRY="${2:-}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

[ -f "$PKG/pubspec.yaml" ] || { echo "no pubspec at $PKG/pubspec.yaml" >&2; exit 1; }

restore() {
  # Restore each path on its own — a single `git checkout` aborts (restoring
  # nothing) if any pathspec is missing, and not every package has an example.
  git checkout -- pubspec.yaml "$PKG/pubspec.yaml" 2>/dev/null || true
  if [ -f "$PKG/example/pubspec.yaml" ]; then
    git checkout -- "$PKG/example/pubspec.yaml" 2>/dev/null || true
  fi
}
trap restore EXIT

# Strip `resolution: workspace` from the package (and its bundled example, which
# ships inside the archive and is analysed by pana), plus the `workspace:` block
# from the repo root, so everything resolves standalone exactly as pub.dev will.
sed -i.bak '/^resolution: workspace$/d' "$PKG/pubspec.yaml" && rm -f "$PKG/pubspec.yaml.bak"
[ -f "$PKG/example/pubspec.yaml" ] && { sed -i.bak '/^resolution: workspace$/d' "$PKG/example/pubspec.yaml" && rm -f "$PKG/example/pubspec.yaml.bak"; }
sed -i.bak '/^workspace:$/d; /^  - packages\//d' pubspec.yaml && rm -f pubspec.yaml.bak

# Scalar (not an array): macOS bash 3.2 + `set -u` errors on an empty
# "${array[@]}". An unset-then-set scalar expands to nothing safely when unquoted.
pubflag=""
case "$DRY" in
  --dry-run) pubflag="--dry-run" ;;
  --force) pubflag="--force" ;;    # non-interactive (CI / OIDC)
  "") ;;
  *) echo "unknown flag: $DRY (use --dry-run or --force)" >&2; exit 64 ;;
esac

echo ">> Publishing $PKG (resolution: workspace stripped)..."
# Force pub.dev — the repo's default PUB_HOSTED_URL may point at a private mirror.
# $pubflag is intentionally unquoted so an empty value expands to no argument.
( cd "$PKG" && PUB_HOSTED_URL="https://pub.dev" dart pub publish $pubflag )
