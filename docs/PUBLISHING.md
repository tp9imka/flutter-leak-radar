# Publishing the flutter-leak-radar suite

The ordered, dependency-safe sequence for publishing the suite to pub.dev.

## Automated: sync constraints, then `tool/publish-all.sh`

Every release round:

1. **`tool/sync-constraints.sh`** — pins each intra-repo dependency constraint to
   `^<current version>` of the target package, so upper tiers *require* (not just
   *allow*) the latest lower tiers. A plain `^0.2.0` lets a consumer stay on a
   stale transitive version; pinning the lower bound forces the current one. Any
   package whose constraints change must be bumped + republished — the script
   prints which. (`--check` mode gates this in CI.)
2. **`tool/publish-all.sh --dry-run`** validates packaging.
3. **`tool/publish-all.sh`** publishes in tier order (0 → 1 → 2), waiting for
   pub.dev visibility between tiers. `--tier N` publishes a single tier.

Tiers (in the script): **0** core (`radar_ui`, `radar_trace`, `leak_graph`) → **1**
radars (`flutter_leak_radar`, `flutter_perf_radar`) → **2** umbrella (`radarscope`).
`flutter_leak_radar_lint` is independent (own cadence). Everything else in the
repo — `flutter_leak_radar_devtools`, `radar_workbench`, `radar_native`,
`radar_native_host`, `radar_desktop` — is `publish_to: none` and never ships to
pub.dev (see "Internal, never published" below).

## Current pub.dev versions (source of truth: each package's `pubspec.yaml`)

| Package | Version | Tier |
|---|---|---|
| `radar_ui` | 0.3.1 | 0 |
| `radar_trace` | 0.2.0 | 0 |
| `leak_graph` | 0.3.0 | 0 |
| `flutter_leak_radar` | 0.3.0 | 1 |
| `flutter_perf_radar` | 0.1.2 | 1 |
| `radarscope` | 0.1.4 | 2 |
| `flutter_leak_radar_lint` | 0.1.2 | independent |

This table is a snapshot — before a release, re-read the pubspecs rather than
trusting these numbers; they drift the moment a package bumps.

## Internal, never published

These packages/apps declare `publish_to: none` and are intentionally absent
from pub.dev — do not add them to `tool/publish-all.sh` or `publish.yaml`:

| Package / app | Why it's internal |
|---|---|
| `flutter_leak_radar_devtools` | DevTools extension, bundled inside `flutter_leak_radar`'s published archive rather than published standalone |
| `radar_workbench` | Shared analysis engine consumed only by the DevTools extension and Radar Desktop |
| `radar_native` | Pure-Dart native-heap model — an implementation detail of `radar_native_host` and Radar Desktop's Android Profiling, not a public API |
| `radar_native_host` | Host-side Perfetto/`adb` tooling — a development tool, not an SDK for embedding in apps |
| `radar_desktop` | A standalone macOS app, not a library |

**Native symbolization has shipped**: `radar_native_host`'s `symbolize` CLI
and Radar Desktop's in-app "Resolve from .so directory" action both resolve
build-id-matched unstripped `.so` files to function names via
`llvm-symbolizer`. This ships as part of the internal tooling above and has
no pub.dev footprint of its own.

## Preconditions

- You are on `main`, tree clean, and the docs/config changes for this
  release round are already merged.
- `dart`/`flutter` on the stable channel; authenticated to pub.dev
  (`dart pub login`) with an account allowed to publish these packages.
- Use **`tool/publish.sh`** — it strips the `resolution: workspace` bits (which
  pub.dev's pana cannot resolve) for the publish only, then restores them, and
  publishes to pub.dev (overriding any `PUB_HOSTED_URL` pointing at a private
  registry). **Always `--dry-run` first.**
- If `flutter_leak_radar_devtools` changed since the last bundle build, run
  `tool/build_devtools_extension.sh` before publishing `flutter_leak_radar` —
  the bundled build inside `flutter_leak_radar`'s archive must reflect the
  extension's current UI.

## Dependency tiers — publish a tier and wait until it is live before the next

- **Tier 0** (no sibling deps): `radar_ui`, `radar_trace`, `leak_graph`
- **Tier 1** (need tier 0 on pub.dev): `flutter_leak_radar` (needs `leak_graph ^0.2.2` + `radar_ui ^0.2.0`), `flutter_perf_radar` (needs `radar_trace ^0.1.2` + `radar_ui ^0.2.0`)
- **Tier 2** (needs tier 1): `radarscope` (needs `flutter_leak_radar`, `flutter_perf_radar`, `radar_trace`, `radar_ui`)

> A dependent package's `--dry-run` will FAIL to resolve until its dependencies
> are actually on pub.dev. That's expected — publish tier by tier.

## Per-package procedure

```bash
tool/publish.sh packages/<pkg> --dry-run   # 1. validate (0 warnings)
tool/publish.sh packages/<pkg>             # 2. publish
```

For a package's **first-ever** publish: after the manual publish, on pub.dev →
the package → **Admin → Automated publishing → enable "Publishing from GitHub
Actions"** (repo `tp9imka/flutter-leak-radar`, tag pattern
`<pkg>-v{{version}}`). Thereafter release via
`git tag <pkg>-v<version> && git push origin <tag>` (the `publish.yaml`
workflow already listens for these tags — see its header comment for the
current tier order).

Validate each publish: open `https://pub.dev/packages/<pkg>/score` (pana runs
server-side, ~a few minutes) and confirm the score.

## Post-publish validation ("validate the points")

- Each package page shows the expected version with a **green analysis** and no
  resolution errors.
- pana points: expect **160/160** for `radar_ui`, `radar_trace`, `leak_graph`,
  `flutter_leak_radar`, `flutter_perf_radar`, `radarscope`. `flutter_leak_radar_lint`
  is capped at **150/160** (`custom_lint_builder` pins `analyzer ^8` vs the
  latest major — an ecosystem cap, unfixable).
- CLI works: `dart pub global activate leak_graph` then `leak_capture` (or
  `dart run leak_graph:capture`) connects and dumps a snapshot.
- A fresh app can `flutter pub add radarscope` and
  `import 'package:radarscope/radarscope.dart';` → `Radar.init(RadarConfig.standard())`.
- In DevTools, enabling the **Leak Radar** extension shows the redesigned Memory
  UI (capture list, root-grouped retaining paths, composable filters).

## Later / conditional

- `flutter_leak_radar_lint`: only publish when its rules change **and** you have
  confirmed the change isn't already in the live version (`0.1.2` as of this
  writing).
