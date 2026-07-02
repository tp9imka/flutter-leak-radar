#!/usr/bin/env bash
#
# Pins every intra-repo dependency constraint to `^<current version>` of the
# target package, so upper tiers REQUIRE the latest lower tiers (a plain `^x.y.z`
# only *allows* newer versions — it does not force them, so consumers can stay on
# stale transitive versions). Single source of truth: each package's own
# `version:` field. Idempotent.
#
#   tool/sync-constraints.sh          # rewrite constraints in place
#   tool/sync-constraints.sh --check  # report stale constraints; exit 1 if any (CI gate)
#
# After a rewrite, any package whose constraints changed must be re-published
# with a version bump — the script prints exactly which ones.
#
# Deliberately avoids bash-4 associative arrays (macOS ships bash 3.2).
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

pkg_field() { awk -F': ' -v k="$1" '$1==k{print $2; exit}' "$2"; }

# Local package dirs (dir name == package name in this repo, but we read `name:`
# to be robust).
DIRS=()
for d in packages/*/; do DIRS+=("$(basename "$d")"); done

stale=0
changed=""
for f in packages/*/pubspec.yaml; do
  self="$(basename "$(dirname "$f")")"
  for depdir in "${DIRS[@]}"; do
    [ "$depdir" = "$self" ] && continue
    depname="$(pkg_field name "packages/$depdir/pubspec.yaml")"
    depver="$(pkg_field version "packages/$depdir/pubspec.yaml")"
    [ -n "$depname" ] && [ -n "$depver" ] || continue
    want="^$depver"
    # Current caret constraint for this dep in $f, if it declares one.
    cur="$(awk -v d="$depname:" '$1==d && $2 ~ /^\^/ {print $2; exit}' "$f")"
    [ -n "$cur" ] || continue
    [ "$cur" = "$want" ] && continue

    stale=1
    case " $changed " in *" $self "*) ;; *) changed="$changed $self" ;; esac
    if [ "$CHECK" = 1 ]; then
      echo "STALE  $self → $depname: $cur ⇒ $want"
    else
      sed -i.bak -E "s|^([[:space:]]*${depname}:)[[:space:]]*\^[^[:space:]#]*|\1 ${want}|" "$f"
      rm -f "$f.bak"
      echo "SET    $self → $depname: $cur ⇒ $want"
    fi
  done
done

if [ "$CHECK" = 1 ]; then
  if [ "$stale" = 1 ]; then
    echo
    echo "Intra-repo constraints are stale. Run tool/sync-constraints.sh, then bump" >&2
    echo "the version + CHANGELOG of each changed package before publishing." >&2
    exit 1
  fi
  echo "All intra-repo constraints are current."
  exit 0
fi

echo
if [ -n "$changed" ]; then
  echo "Constraints changed in:$changed"
  echo "→ Bump the version + CHANGELOG of any of these already published to pub.dev,"
  echo "  then publish (tool/publish-all.sh)."
else
  echo "No changes — all intra-repo constraints already current."
fi
