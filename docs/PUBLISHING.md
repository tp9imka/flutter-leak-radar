# Publishing the flutter-leak-radar suite

The ordered, dependency-safe sequence for publishing the suite to pub.dev.

## Automated: `tool/publish-all.sh`

For a routine round, `tool/publish-all.sh --dry-run` validates tier-0 packaging,
then `tool/publish-all.sh` publishes the changed packages in tier order, waiting
for pub.dev visibility between tiers. Edit the `TIER0` / `TIER1` arrays in the
script to match what changed. The manual per-package steps below remain the
source of truth for first-time publishes and automated-publishing setup.

### Round: devtools persistence + overlay UX + tracer/perf improvements

| Publish | Version | Tier | Note |
|---|---|---|---|
| radar_ui | 0.1.1 | 0 | ripple feedback on chips/sort headers |
| radar_trace | 0.1.2 | 0 | `dedupKey` duplicate detection |
| leak_graph | 0.2.2 | 0 | `classPathDistributions` |
| flutter_leak_radar | 0.2.1 | 1 | overlay UX + refreshed bundled extension |
| flutter_perf_radar | 0.1.1 | 1 | `dedupKey`, stall detail, timeline crash fix |

**Skip (unchanged):** `radarscope` (its `^` constraints pick up the new tier-0/1
versions automatically), `flutter_leak_radar_lint`, and
`flutter_leak_radar_devtools` (`publish_to: none`).

## Preconditions

- You are on `main`, tree clean, **after PR #89 (publish prep) is merged**.
- `dart`/`flutter` on the stable channel; authenticated to pub.dev
  (`dart pub login`) with an account allowed to publish these packages.
- Use **`tool/publish.sh`** — it strips the `resolution: workspace` bits (which
  pub.dev's pana cannot resolve) for the publish only, then restores them, and
  publishes to pub.dev (overriding any `PUB_HOSTED_URL` pointing at a private
  registry). **Always `--dry-run` first.**
- If `flutter_leak_radar_devtools` changed since the last bundle build, run
  `tool/build_devtools_extension.sh` before publishing `flutter_leak_radar`
  (already current as of #87 — the bundled build reflects the Memory redesign).

## What ships this round

> **Note:** Tier 0 was published once from a pre-publish-prep checkout, so
> `radar_trace 0.1.0` and `leak_graph 0.2.0` are live but with stale docs
> (their *code* is correct). pub.dev versions are immutable, so the docs fixes
> ship as patch re-publishes below. `radar_ui 0.1.0` was byte-identical to
> `main`, so it needs no re-publish.

| Publish | Version | Note |
|---|---|---|
| radar_ui | 0.1.0 | ✅ already live & byte-identical — **skip** |
| radar_trace | 0.1.1 | re-publish (README docs; 0.1.0 already live) |
| leak_graph | 0.2.1 | re-publish (README rewrite + `leak_capture` executable; 0.2.0 already live) |
| flutter_leak_radar | 0.2.0 | upgrade from 0.1.1 |
| flutter_perf_radar | 0.1.0 | first publish |
| radarscope | 0.1.0 | first publish (umbrella) |

**Skip:** `flutter_leak_radar_lint` (0.1.2 already live, unchanged this round) ·
`flutter_leak_radar_devtools` (`publish_to: none`).

## Dependency tiers — publish a tier and wait until it is live before the next

- **Tier 0** (no sibling deps): `radar_ui`, `radar_trace`, `leak_graph`
- **Tier 1** (need tier 0 on pub.dev): `flutter_leak_radar` (needs `leak_graph 0.2.0` + `radar_ui 0.1.0`), `flutter_perf_radar` (needs `radar_trace 0.1.0` + `radar_ui 0.1.0`)
- **Tier 2** (needs tier 1): `radarscope` (needs `flutter_leak_radar`, `flutter_perf_radar`, `radar_trace`, `radar_ui`)

> A dependent package's `--dry-run` will FAIL to resolve until its dependencies
> are actually on pub.dev. That's expected — publish tier by tier.

## Per-package procedure

```bash
tool/publish.sh packages/<pkg> --dry-run   # 1. validate (0 warnings)
tool/publish.sh packages/<pkg>             # 2. publish
```

3. **First-publish packages** (`radar_ui`, `radar_trace`, `flutter_perf_radar`,
   `radarscope`): after the manual publish, on pub.dev → the package →
   **Admin → Automated publishing → enable "Publishing from GitHub Actions"**
   (repo `tp9imka/flutter-leak-radar`, tag pattern `<pkg>-v{{version}}`).
   Thereafter release via `git tag <pkg>-v<version> && git push origin <tag>`
   (the `publish.yaml` workflow already listens for these tags).
4. **Validate the points**: open `https://pub.dev/packages/<pkg>/score`
   (pana runs server-side, ~a few minutes) and confirm the score.

## Ordered checklist

1. **radar_ui 0.1.0** — ✅ already published, byte-identical to `main`. **Skip.**
2. **radar_trace 0.1.1** — dry-run → publish → enable automated → verify. Docs-only re-publish (0.1.0 is already live).
3. **leak_graph 0.2.1** — dry-run → publish → verify. README rewrite + `leak_capture` executable; library code is unchanged from the already-live 0.2.0.
   - ⏳ Wait until `radar_trace 0.1.1` and `leak_graph 0.2.1` are visible on pub.dev.
4. **flutter_leak_radar 0.2.0** — dry-run (resolves now that `leak_graph 0.2.0` + `radar_ui 0.1.0` are live) → publish/tag → verify. Ships the refreshed bundled DevTools extension and `share_plus >=10.0.0 <14.0.0`.
5. **flutter_perf_radar 0.1.0** — dry-run → publish → enable automated → verify.
   - ⏳ Wait until tier 1 is live.
6. **radarscope 0.1.0** — dry-run → publish → enable automated → verify. (Requires `share_plus ^13.1.0` by design — it uses the `SharePlus.instance` API.)

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
  confirmed the change isn't already in the live 0.1.2.
