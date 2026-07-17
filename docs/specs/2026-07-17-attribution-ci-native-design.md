# Attribution, CI, and the Native Lane — consolidated design

_Date: 2026-07-17. Status: **approved** (adversarially reviewed by two independent
review passes — product/UX and architecture — findings folded in below).
Companion plan: `docs/plans/2026-07-17-attribution-ci-native-plan.md`._

## 1. Goal

Three axes, one release train:

- **(A) Whose leak is it** — attribute every leaked class to its owner (project /
  dependency / framework / SDK), group and highlight by package, and give the
  retaining path a "your code holds it HERE" anchor. Make the first screen after a
  capture→act→capture diff answer *"which of these are MINE?"* by default.
- **(B) Radar in CI** — headless memory tracking around a real app run, a gate with
  exit codes a pipeline can trust, and an end-of-run report readable in 30 seconds.
- **(C) The native lane** — productize the field-proven Android native workflow
  (dumpsys meminfo / fd / thread trends, settle windows, batch2-minus-batch1 slope,
  plateau-vs-monotonic verdicts) as CLI verbs for automation and a desktop pane.

Field grounding: the 2026-06/07 KATIM leak campaign. What worked: meminfo/PSS trends,
fd + thread counting, checkpoint methodology, VM `getMemoryUsage.externalUsage`
(caught a 438 MB `ui.Image` pool), per-class wrapper counts vs baseline,
profile-mode-only measurement. What failed: single-shot heap dumps, debug-mode
measurement (inspector pins produce fake leaks), in-process dump side effects.

## 2. Non-goals (this round)

- Dominator/retained-size computation (severity uses shallow-bytes×instances proxy).
- Source links on every retaining-path hop (anchor-hop-only file:line on desktop
  ships; the full G15 borrow stays future work).
- smaps PSS-by-mapping rollup (userdebug/root-gated; Lane A routes verdicts from
  ungated sources; deferred pending a future spike doc).
- Self-contained HTML report (md/github/json only; HTML revisited on demand).
- Lint SARIF/baseline; DevTools-extension native lane (adb unreachable from web);
  iOS/desktop-native samplers; Perfetto UI embedding; `.radarworkspace` zip format.
- Desktop connected-mode full heap-snapshot capture (trend polling only; the
  README/guide claim is corrected by the Device Monitor scope note).

## 3. Phase A — attribution

### 3.1 Origin + anchor core (`leak_graph`, minor → **0.3.0**)

- `ClassOrigin` enum `{project, dependency, flutterFramework, dartSdk, unknown}` and
  `OriginClassifier(projectPackages)`. `dart:*` → dartSdk; the Flutter-framework set
  (`flutter`, `flutter_test`, `flutter_localizations`, `flutter_driver`,
  `flutter_web_plugins`, `sky_engine`) → flutterFramework; project set → project;
  any other `package:` → dependency. Extends `AppPackageSet` (which stays);
  configured via `GraphAnalysisOptions.projectPackages`.
- **Declared vs retained-by.** Origin of the *declaring* library alone misattributes
  the payload classes that dominate real diffs (`String`, `_List`, `Uint8List` are
  dartSdk but retained by user code). Histogram/diff rows carry two signals:
  `declaredOrigin` (from `ClassCount.libraryUri`) and `dominantAnchor` — the dominant
  retaining anchor package derived from the existing `classRootProfiles` /
  `classPathDistributions`. Byte-mass rollups aggregate by **anchor** package
  (labeled "retained via"); declared-package rollup is the secondary view. All
  numbers labeled shallow/declared honestly.
- `GraphHop.libraryUri` (nullable). **Excluded from `==`/`hashCode` and from
  `pathSignature`** — cluster identity must not shift (Phase B baselines key on it).
  A golden-signature regression test pins this. `buildHops` gains a parallel
  library-uri list (public API change → part of the 0.3.0 bump).
- Anchor plumb-through: `LeakRecord.anchorHopIndex` so UIs can highlight the anchor
  hop in the serialized path, and `GraphLeakCluster.attributionClassName` /
  `attributionLibraryUri` (nullable) including `toJson`/`fromJson` — today the
  anchor dies unserialized on `LeakRecord` and never reaches bundles.
- `PackageRollup` (per anchor package: origin, classes, instances, shallowBytes,
  clusterCount) on `GraphAnalysisResult` + JSON. All new JSON carries
  `schemaVersion`.
- Project-package detection chain, **with the chosen source reported** (never present
  a heuristic as configured truth): explicit config → VM `rootLib` package →
  `AppPackageSet.autoDetect`. Pubspec/pubspec.lock readers ship in an additive
  `package:leak_graph/io.dart` entrypoint (the main barrel is unchanged).

### 3.2 Runtime (`flutter_leak_radar`, minor bump)

- Public `LeakFinding.origin`; auto-detect the app's own package for
  `GraphScan.appPackages` via the probe's existing `VmService` connection
  (`getIsolate(...).rootLib`), falling back per the chain above (the in-process VM
  service is often unreachable on physical devices; file-snapshot path has no
  connection at all). Kills the silent `appPackages: const []` attribution-off
  default.
- Populate the declared-but-never-set `LeakReport.heapBytes` and per-finding bytes
  (feeds severity + reports).

### 3.3 Design system (`radar_ui`, minor bump)

- `OriginTokens`: project = violet (the free hue — NOT `accent`, which means
  healthy/negative-delta everywhere else); dependency = neutral-strong;
  framework/sdk = muted. **One ownership palette across lanes**: the native
  `moduleKindColor` palette (today accent=plugin, info=app — inverted vs any sane
  Dart-side choice) migrates to OriginTokens semantics.
- `OriginChip`; status chips NEW / KNOWN / ACK / GONE (built on `RadarTag`).
- No per-row origin tinting (severity owns the row-tint channel); chips + group
  headers + a left-edge tick carry origin.
- The multi-series time chart is **Phase C** work (its only consumer).
- _Correction (review round): the Radar design system is **dark-only** — a
  single fixed palette, no light theme. `OriginTokens` follows the
  `SeverityTokens` template as one dark palette (not a light/dark pair)._

### 3.4 Workbench views (`radar_workbench`) + per-host wiring

Views are shared; navigation is not. Every new view is wired twice: `RadarView`
enum + LeftRail + `_buildContent()` (DevTools host) and `DesktopView` + rail +
`desktop_shell` switch (desktop host). Keep desktop wiring additive — the
first-run-guide branch touches the same files and will need manual conflict
resolution when it lands.

- `originOf()` / anchor helpers beside `libraryLabel()` in `mem_format.dart`.
- **Post-diff default state (the S1 contract):** grouped by anchor package; project
  group pinned first and expanded; dependency groups collapsed showing rollup
  deltas; framework/sdk collapsed under one "runtime" group — visible, never
  auto-hidden. Within groups: Δbytes desc. "Hide framework" is a preset chip.
  One shared grouping scaffold serves ClassHistogramView + DiffTable (the histogram
  has no library column today — adding origin is a real column/layout change at
  34 px row height, width-budgeted).
- Retaining paths: hops colored by origin; anchor hop highlighted ("your code holds
  it HERE"); hop text selectable + copy-path button. Desktop only: anchor-hop
  file:line via `package_config` resolution + click-to-open; DevTools gets copy.
- Filters: `package:` and `origin:` fields in `FilterExpression`; hide-framework
  preset chip.
- **Leak-clusters view** (new; both hosts): renders the already-serialized clusters
  with confidence, origin, anchor, and `stats.warnings` (capture failures stop
  being invisible). Ranking: confidence desc → project-anchor first →
  shallowBytes×instances.
- **Cross-session leak identity:** triage state persisted in the session store —
  `pathSignature → {firstSeen, status: new|known|acknowledged, note}`. Clusters +
  diff views render NEW / KNOWN / ACK / **GONE** chips and a "since last session"
  toggle. GONE is the payoff: positive confirmation a fix landed. Same signature
  machinery the CI gate uses; no repo files involved. `PersistedSession.version`
  is actually checked on read from now on.
- Project-package sources per host: DevTools `dtdManager.projectRoots` → pubspec;
  desktop workspace pubspec.lock auto-detect; manual override field in both.

### 3.5 Passing fixes

- radarscope quick-menu "Open Performance" opens the Leaks tab
  (`radar_overlay.dart` — both callbacks identical; pass `initialTab: 1`).

## 4. Phase B — Radar in CI

### 4.1 Series + verdict core (**`radar_trace`**, minor bump)

Home rationale: pure, published, deps = `meta` only; both lanes consume it
(`radar_ci → radar_trace`, `radar_native → radar_trace`; no cycles). Putting it in
leak_graph would drag `vm_service/args` into the native lane and version-couple
every dependent.

- `MetricSeries` (named, unit-tagged, timestamped samples; **gap markers are
  first-class** — never interpolate) and `SeriesVerdict`
  `{monotonicGrowth, plateau, noisy, insufficientData}` computed via settle-window
  trimming, batch2-minus-batch1 init-free slope, and plateau detection.
  `schemaVersion` on the JSON.

### 4.2 leak_graph CLI hardening

- `analyze` added to pubspec `executables:`; new `diff` subcommand
  (`ClassCountDiff.toJson`); baseline in/out (`--baseline`, `--write-baseline`);
  threshold flags; exit codes **0 ok / 1 usage / 2 tool failure / 3 gate failed**.
- `--format json|md|github`. The github renderer's 30-second contract: line 1 =
  verdict; then ≤3 NEW project-anchor clusters, each with anchor hop and delta vs
  base; everything else in `<details>`.
- NEW-vs-KNOWN via `pathSignature`, rendered with the nearest-miss KNOWN signature
  (refactor churn must not read as regression); signature-stability caveats
  documented. A baseline with older `schemaVersion` → insufficient-data, never
  all-NEW.

### 4.3 `radar_ci` (new package #13, pure Dart bin, `publish_to: none` initially)

Deps: radar_trace, leak_graph, radar_native, radar_native_host, vm_service.

- `radar_ci run` — attach to a ws URI, or spawn `--cmd` preferring
  `flutter run --machine` (JSON `app.debugPort` event) with the existing
  `AndroidVmServiceDiscovery` logcat regex as the attach-path reuse; settle;
  N checkpoints: `getMemoryUsage` per isolate (heap + **externalUsage** as separate
  metrics), `getAllocationProfile` top-N per class, full heap snapshot every K;
  optional `--exec` / `--call-extension` driver hook between checkpoints; writes a
  versioned `run.json` stamped with device/flutter-version/mode metadata.
- `radar_ci gate` — **verdict-based by default** (fail on monotonicGrowth of a
  project-anchor cluster at ≥ probable confidence); byte-absolute thresholds are
  opt-in flags. Exit codes as above.
- `radar_ci report` — run.json (+ native session) → md/github/json. **The single
  report entry point for all lanes** (no `report` verb on radar_native_host).
- Baseline lifecycle documented + templated in `examples/ci/memory.yaml`:
  main-branch artifact publish → PR fetch-and-compare, plus the two-run-compare
  alternative. A checked-in baseline is *not* the blessed default.
- **Hermetic e2e gate test in repo CI (non-negotiable):** a pure-Dart planted-leak
  fixture; `radar_ci run` attaches over vm_service (no Flutter, no emulator);
  CI asserts exit 3 on the leaky variant and exit 0 on the fixed one. Report/renderer
  dogfood uses synthesized fixtures (in-memory `HeapGraphView` fake → tiny
  run.json), never committed real heap dumps. A live Flutter-desktop lane is
  stretch, `workflow_dispatch` only.
- **Adoption front door:** `radar_ci run --cmd "flutter run --profile ..."` with
  sane defaults (auto settle, 3 checkpoints, report to stdout + file, top-3
  project-anchor suspects first) goes in the README quick start; `example/` ships
  the driver-extension scenario.

## 5. Phase C — the native lane

### 5.1 `radar_native` (pure; + `radar_trace` dep)

- Lane A `TriageTimeline` (revives the 2026-07-02 design): typed columns — Java
  HeapAlloc, Native PSS, Graphics/memtrack, Code, TOTAL PSS, RssAnon, VmRSS,
  Threads, fd classes — per-column `SeriesVerdict` + a router verdict
  (java | dart | native-malloc | graphics | fd | thread, ranked by growth share).
- `NativeModuleDiff` / `NativeModuleSummary` / `NativeDiffStatus` gain `toJson`.

### 5.2 `radar_native_host` samplers + CLI verbs

All samplers go through the `AdbRunner` seam, fake-runner tested, and follow the
**parsed-or-unmeasured rule**: a format miss NEVER parses as 0 — it yields
`measured: false`, propagates to `SeriesVerdict.insufficientData`, renders as
"not measured". Each sampler's tests include a malformed-output fixture.

> **Implementation status (2026-07-17):** smaps PSS-by-mapping stays deferred
> (userdebug/root-gated) — Lane A routes verdicts from ungated `dumpsys` /
> `/proc` sources only, so a non-rooted device is fully covered.

- Samplers: dumpsys meminfo summary; `/proc/pid/status` (VmRSS/RssAnon/Threads);
  fd classification (readlink buckets: sync_file / dmabuf / ashmem / total);
  thread-name counts (`/proc/PID/task/*/comm`); dumpsys gfxinfo
  GraphicBufferAllocator total + buffer count.
- CLI verbs beside `symbolize` (same injectable template + exit codes):
  - `sample` — interval/duration; **overnight-robust**: adb auto-reconnect, PID
    re-resolution (restart logged as an event), gap markers, periodic session
    flush (a crash at hour 7 loses minutes, not the night).
  - `mark` — append a timestamped label to a running/finished session.
  - `capture` — heapprofd wrap + preflight (heapprofd availability, profileable/
    debuggable check, non-empty `heap_profile_allocation` validation) replacing
    the fixed-sleep flake.
  - `diff` — native profiles → json/md.
  - `triage` — Lane A router over a sample session; `--compare a/ b/` diffs two
    sessions per column (verdict + slope A vs B) — the before-fix-night vs
    after-fix-night loop.
- `radar_ci run --native` co-drives sampling during a run; lanes merge on host
  wall-clock in `run.json`.

> **Implementation status (2026-07-17):** shipped as `radar_ci run
> --native-package <pkg> [--native-interval] [--native-device]`, folding an
> additive `nativeTimeline` into `run.json`. The native verdict gate is
> **opt-in** this release (`gate --gate-native`; a not-measured column never
> fails, and `--gate-native` on a run with no native lane refuses rather than
> passing silently); `report` always shows a native per-column table and folds
> native growth into its informational verdict.

### 5.3 `radar_desktop` Device Monitor pane (**import-first**)

- New `RadarTimeSeriesChart` in radar_ui (new component — RadarTrendChart is
  Y-values-only): multi-series, time axis, legend, markers, shaded settle windows,
  threshold line.
- v1: import a `sample`/`radar_ci` session JSON → columns, marks, per-column
  verdict chips, batch-slope readout, session-vs-session compare. Matches the
  repo's own import-first ruling for Lane A.
- v1.1 (same seam, stretch): live polling + heapprofd start/stop from the pane.

> **Implementation status (2026-07-17):** the Device Monitor pane ships
> **import-first (v1)** — session import + charts + per-column verdicts +
> compare. Live polling / heapprofd start-stop from the pane (v1.1) stays
> deferred on the same seam.
- Connected mode: poll `getMemoryUsage` — heapUsage and externalUsage as **two
  separate series** (a merged line hides the external-pool pattern).

## 6. Versioning, CI, and process

- Version bumps declared up front: leak_graph **0.3.0**; flutter_leak_radar,
  radar_trace, radar_ui minor bumps; radar_ci `publish_to: none`.
- `tool/sync-constraints.sh --check` wired into `ci.yaml` in the first Phase-A PR.
- `ci.yaml` additions: radar_ci analyze/test; the hermetic gate e2e; a report
  step-summary demo (`$GITHUB_STEP_SUMMARY`).
- Branch/PR topology: integration branch `feat/attribution-ci-native`; each phase
  lands as small house-style sub-PRs targeting the integration branch; one final
  integration PR → main. No GitHub stacks.
- Toolchain: analyze/test with Flutter stable 3.44.x (matches CI); devtools
  extension tests via `flutter test --platform chrome`.

## 7. Risk register

| Risk | Mitigation |
|---|---|
| Published-package semver knot (path-resolution hides mismatches) | bumps declared up front; constraint check in CI from PR 1 |
| Baseline identity drift (A changes hop construction while B keys on signatures) | golden signature-stability test in Phase A; older baseline schemaVersion → insufficient-data |
| Silent-zero adb samplers (OEM format variance parses as 0 → "no leak") | parsed-or-unmeasured rule; malformed fixture per sampler; unmeasured → insufficientData |
| Desktop shell conflicts with first-run-guide WIP | branch from main; keep pane wiring additive; expect manual resolution |
| In-process VM service unreachable on physical devices | detection chain with reported source; never a heuristic presented as truth |
