# flutter-leak-radar — Follow-ups & Roadmap

_Last refreshed: 2026-07-17 (end of the attribution / CI / native train)._

## Where things stand

The **attribution + CI + native-lane train** landed on
`feat/attribution-ci-native`. Design:
[`docs/specs/2026-07-17-attribution-ci-native-design.md`](specs/2026-07-17-attribution-ci-native-design.md);
phase plans in [`docs/plans/`](plans/) (`2026-07-17-phase-{a,b,c}-*.md`).

### Shipped this train

**Phase A — attribution (whose leak is it):**
- `leak_graph` **0.3.0** — `ClassOrigin` / `OriginClassifier`, `GraphHop.libraryUri`
  (excluded from `==`/`hashCode`), anchor plumb-through
  (`attributionClassName`/`LibraryUri`, `anchorHopIndex`), `PackageRollup`
  anchor/declared rollups, and a pubspec-reading `package:leak_graph/io.dart`
  entrypoint. Owner attribution anchors the `pathSignature` at the app owner
  (root→anchor), so **every app-anchored cluster re-keys versus 0.2.2** —
  pre-0.3.0 baselines/exports are not signature-comparable (re-baseline). All
  new JSON carries `schemaVersion`.
- `flutter_leak_radar` **0.3.0** — `LeakFinding.origin` + shallow `bytes`,
  populated `LeakReport.heapBytes`, and a reported `projectPackageSource`
  detection chain (explicit → rootLib → autoDetect → none).
- `radar_ui` **0.3.0** — `OriginTokens` (project = violet, one ownership palette
  across lanes), `OriginChip`, NEW/KNOWN/ACK/GONE status chips.
- `radar_workbench` — origin grouping, leak-clusters view, cross-session leak
  identity (NEW/KNOWN/ACK/**GONE**), wired into both hosts.

**Phase B — Radar in CI:**
- `radar_trace` **0.2.0** — gap-first `MetricSeries` + `assessSeries` /
  `SeriesVerdict` (settle trim, batch2−batch1 slope, Mann–Kendall growth
  certification). Both lanes consume it; no cycles.
- `leak_graph` CLI — `analyze`/`diff`, baseline in/out, threshold flags,
  exit codes `0/1/2/3`, `--format md|github|json`, NEW-vs-KNOWN by signature.
- `radar_ci` (new, `publish_to: none`) — `run` (attach/spawn, gap-aware series,
  checkpoints, heap snapshots), verdict-based `gate`, unified `report`
  (the single report entry point for all lanes). Hermetic planted-leak e2e in
  CI; copy-and-adapt templates in
  [`examples/ci/memory.yaml`](../examples/ci/memory.yaml).

**Phase C — the native lane:**
- `radar_native` — Lane A `TriageTimeline` + per-column `triage` router;
  `NativeModuleDiff`/`Summary`/`DiffStatus` gained `toJson`.
- `radar_native_host` — side-effect-free `adb` samplers (meminfo, `/proc`
  status, fd classes, threads, gfxinfo) under the parsed-or-unmeasured rule,
  and CLI verbs `sample` / `mark` / `capture` / `diff` / `triage`
  (overnight-robust; `--compare a/ b/` for the before-fix vs after-fix loop).
- `radar_ui` **0.3.1** — dark-only `RadarTimeSeriesChart` (Lane C's consumer).
- `radar_desktop` — **import-first** Device Monitor pane (import a `sample` /
  `radar_ci` session → columns, marks, per-column verdicts, session compare).
- `radar_ci run --native-package …` — co-drives the native lane during a run;
  `run.json` gains an additive `nativeTimeline`; `gate --gate-native` (opt-in)
  and a native table in `report`.

### Deferred (with pointers)

- **Native gate is opt-in this release.** `gate --gate-native` must be asked
  for; native growth is informational in `report`. Revisit default-on once the
  samplers have on-device mileage.
- **smaps PSS-by-mapping rollup** — userdebug/root-gated; Lane A routes
  verdicts from ungated sources instead. Deferred pending a future spike doc
  (spec §2).
- **Device Monitor live polling / heapprofd start-stop from the pane** — the
  v1.1 stretch on the same seam; v1 is import-only (spec §5.3).
- **Desktop connected-mode full heap-snapshot capture** — trend polling only
  (heapUsage + externalUsage as two series); snapshot capture stays
  offline / Android-profiling (spec §2).
- **Dominator/retained-size**, **per-hop source links** (anchor-hop-only
  file:line ships; full G15 borrow is future work), **self-contained HTML
  report**, **lint SARIF/baseline**, **DevTools-extension native lane** (adb
  unreachable from web), **iOS / desktop-native samplers**, **Perfetto UI
  embedding**, **`.radarworkspace` zip** — all non-goals this round (spec §2).
- **radar_ci** stays `publish_to: none`; publish once the native lane has field
  mileage.

### radar_ci small fast-follows (carried)

- **Decouple snapshot/analysis from the sampling hot path** — heap dumps +
  in-process analysis run inline at each checkpoint today, pausing sampling;
  once off the hot path the `--snapshot-every` default drops to start/end-only.
- **Worker-isolate heaps are not analysed** — snapshots target the main isolate
  only.

## The 0.1.x milestone (still true)

- `leak_graph`, `flutter_leak_radar`, `flutter_leak_radar_lint` published;
  retaining-path detection, all 7 lint rules, the in-app dashboard/overlay, and
  `tool/publish.sh` are done.
- `flutter_leak_radar_lint` reaches **160/160** pana only when
  `custom_lint_builder` ships analyzer-9+ support (it pins `analyzer ^8`; the
  whole custom_lint ecosystem lags).
