# Phase C — Native Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development.
> Implementers read the real files named per task; this plan pins contracts.
> Spec: `docs/specs/2026-07-17-attribution-ci-native-design.md` §5. Revives the
> Lane A design in `docs/specs/2026-07-02-native-gpu-leak-analysis-design.md`
> (TriageTimeline) — read it before C1/C2.

**Goal:** The field workflow that cracked the KATIM native leak — meminfo/fd/thread
trends, settle windows, batch slopes, plateau-vs-monotonic verdicts — as CLI verbs an
overnight run can trust and an import-first desktop pane.

**As-built inputs (merged):** radar_trace 0.2.0 `MetricSeries`/`SeriesGap`/
`assessSeries`→`SeriesAssessment` (growth needs ≥~12 assessed samples; gaps first-class);
radar_ci run.json (`RadarRunDocument` schemaVersion 1); radar_ui OriginTokens;
radar_native_host `AdbRunner`/`LazyAdbRunner` seams + `symbolize` CLI template
(exit codes 0/1/2) + `AdbHeapprofdCapture`; radar_native `NativeModuleDiff` et al.

## Global constraints

- Phase A/B global rules apply (worktrees, TDD, conventional commits, toolchain
  `~/development/flutter-latest`, exit codes 0/1/2/3, schemaVersion on new JSON).
- **Parsed-or-unmeasured rule (non-negotiable):** an adb/OEM format miss NEVER parses
  as 0 — it yields `measured: false` → the metric's series records a gap / the column
  reads "not measured" → `SeriesVerdict.insufficientData`. Every sampler ships a
  malformed-output fixture test. This is R3 from the risk register.
- Samplers are side-effect-free on the device (no am dumpheap-style in-process
  allocation; read-only shell commands only).
- All flutter/dart suites relevant to a touched package run before commit; any task
  touching radar_workbench/radar_ui/radar_desktop runs ALL FOUR UI suites
  (workbench, leak_graph, desktop, devtools-chrome) + the layout_width_test pattern.

## Sub-PR grouping (target `feat/attribution-ci-native`)

| PR | Tasks | Branch |
|---|---|---|
| C-PR1 model + samplers | C1 C2 | `feat/c1-native-triage` |
| C-PR2 CLI verbs | C3 C4 | `feat/c2-native-verbs` |
| C-PR3 chart | C5 | `feat/c3-timeseries-chart` |
| C-PR4 desktop pane | C6 | `feat/c4-device-monitor` |
| C-PR5 ci co-drive + docs | C7 | `feat/c5-native-codrive` |

---

### Task C1: TriageTimeline + router verdict (radar_native, pure)

**Files:** read `packages/radar_native/lib/` structure + the 2026-07-02 spec §Lane A
first. Create `lib/src/triage/triage_timeline.dart`, `lib/src/triage/triage_router.dart`;
modify barrel, pubspec (+`radar_trace` dep — pure, acyclic), existing model files ONLY
to add `toJson`/`fromJson` to `NativeModuleDiff`/`NativeModuleSummary`/`NativeDiffStatus`
(read their current shapes; keep `==`/`hashCode` consistent).
**Test:** `test/triage/…` — synthetic series per column; router matrix; JSON round-trips.

**Interfaces — Produces:**
```dart
/// Column identifiers — the Lane A signal set (device-agnostic names).
enum TriageColumn {
  javaHeapKb, nativePssKb, graphicsKb, codeKb, totalPssKb,   // dumpsys meminfo
  rssAnonKb, vmRssKb, threads,                                // /proc/pid/status
  fdTotal, fdSyncFile, fdDmabuf, fdAshmem,                    // /proc/pid/fd
  gfxBufferKb, gfxBufferCount,                                // dumpsys gfxinfo GBA
}

final class TriageTimeline {
  final Map<TriageColumn, MetricSeries> columns;   // absent key = never measured
  final List<TriageMark> marks;                    // labeled checkpoints
  // toJson/fromJson, 'schemaVersion': 1
}
final class TriageMark { final int tMicros; final String label; /* json */ }

final class TriageColumnAssessment {
  final TriageColumn column; final SeriesAssessment assessment; /* json */
}

enum TriageBucket { javaHeap, nativeMalloc, graphics, code, fd, thread, none }

final class TriageVerdict {
  final TriageBucket bucket;            // dominant growing bucket; none = no growth
  final List<TriageColumnAssessment> assessments;  // every measured column
  final String summary;                  // one honest sentence naming the bucket +
                                         // rate, or "no monotonic growth detected",
                                         // or "insufficient data: <which columns>"
  // toJson
}
TriageVerdict triage(TriageTimeline timeline, [AssessOptions options]);
```
Router semantics: assess every measured column; growing columns (monotonicGrowth)
are ranked by growth share — normalize slopePerHour by column family (bytes columns
compare in kb/h; counts in units/h — never cross-compare bytes vs counts; when both
a bytes bucket and a count bucket grow, report the bytes bucket as primary and NAME
the count growth in the summary). Column→bucket map: javaHeapKb→javaHeap;
nativePssKb+rssAnonKb→nativeMalloc; graphicsKb+gfxBuffer*→graphics; codeKb→code;
fd*→fd; threads→thread; totalPssKb/vmRssKb are corroborating, never primary.
insufficientData columns are listed in the summary as not-measured, never counted
as flat.
- [ ] TDD: per-column assessment passthrough; router picks dominant bytes bucket;
      count-growth named alongside; none verdict; not-measured honesty; JSON
      round-trips; NativeModuleDiff/Summary/Status toJson round-trips.
- [ ] Commit `feat(radar_native): TriageTimeline + honest triage router`.

### Task C2: adb samplers (radar_native_host)

**Files:** read `lib/src/capture/` (AdbRunner seam, android_vm_service_discovery
style). Create `lib/src/sample/meminfo_sampler.dart`, `proc_status_sampler.dart`,
`fd_sampler.dart`, `thread_sampler.dart`, `gfxinfo_sampler.dart`,
`sample_snapshot.dart`; modify barrel + pubspec (+radar_native, +radar_trace deps
if absent).
**Test:** per-sampler fixture tests (real captured output samples as fixtures — write
plausible Android 12-14 shaped fixtures + one MALFORMED fixture each).

**Interfaces — Produces:**
```dart
final class SampleValue { final int? value; final bool measured; final String? error; }
// NEVER value=0 on parse failure: measured=false + error set.

final class NativeSampleSnapshot {
  final int tMicros;
  final Map<TriageColumn, SampleValue> values;
  // toJson/fromJson
}

abstract interface class NativeSampler {
  Set<TriageColumn> get columns;
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid);
}
// Implementations: MeminfoSampler (dumpsys meminfo <pkg> — parse the summary table:
// Java Heap/Native Heap/Graphics/Code/TOTAL PSS rows), ProcStatusSampler
// (/proc/<pid>/status: VmRSS/RssAnon/Threads), FdSampler (ls -l /proc/<pid>/fd —
// classify readlink targets: anon_inode:sync_file, dmabuf, ashmem + total; count
// lines defensively), ThreadSampler (cat /proc/<pid>/task/*/comm — total count; a
// per-prefix breakdown API: Map<String,int> topThreadNamePrefixes(n)),
// GfxinfoSampler (dumpsys gfxinfo <pkg> — GraphicBufferAllocator total KB + count;
// mark unmeasured when the section is absent).
final class CompositeSampler implements NativeSampler { /* runs all, merges */ }

/// Builds TriageTimeline columns incrementally from snapshots (host wall-clock),
/// inserting SeriesGap for unmeasured stretches with the sampler's error as reason.
final class TimelineBuilder { void add(NativeSampleSnapshot s); void addMark(String label);
  TriageTimeline build(); }
```
- [ ] TDD: each sampler parses its good fixture to exact values; malformed fixture →
      measured:false + error (NEVER 0); FdSampler classification counts; pid-gone
      (empty output/error exit) → all-unmeasured; TimelineBuilder gap insertion on
      unmeasured runs; composite merge.
- [ ] Commit `feat(radar_native_host): side-effect-free native samplers (meminfo, proc, fd, threads, gfx)`.

### Task C3: `sample` + `mark` verbs — overnight-robust (radar_native_host)

**Files:** read `lib/src/symbolize/symbolize_cli.dart` (the verb template: injectable
seams, env fallbacks, exit codes) + `bin/symbolize.dart`. Create
`lib/src/sample/sample_cli.dart`, `bin/sample.dart`, `bin/mark.dart`; pubspec
executables (`radar_sample`, `radar_mark` — bare names collide too easily).
**Behavior:**
- `radar_sample --package com.example.app [--device SERIAL] --interval 5s
  --duration 8h --out session_dir/ [--flush-every 60s]` — resolves pid via adb
  (`pidof`), samples via CompositeSampler, appends to
  `session_dir/timeline.json` (TriageTimeline JSON, atomically rewritten each flush)
  + `session_dir/meta.json` (package, device, started, schemaVersion).
- **Overnight robustness (test-pinned):** adb command failure → that tick's columns
  unmeasured (gap), sampling continues; device disconnect → retry loop with backoff
  (log to stderr), gap covers the outage; **pid change after reconnect → recorded as
  a mark `process-restart (pid X→Y)` + gap**, sampling continues on the new pid;
  periodic flush every `--flush-every` (default 60s) so a crash loses ≤1 interval;
  SIGINT/SIGTERM → final flush + exit 0 (an interrupted overnight session is still a
  VALID session).
- `radar_mark --session session_dir/ "label"` — appends a TriageMark (reads+rewrites
  timeline.json atomically; safe against a concurrent flush via write-to-temp+rename
  and a retry-on-conflict loop).
- [ ] TDD with a fake AdbRunner: gap-on-failure; reconnect backoff; pid-change mark;
      flush cadence (fake clock); SIGINT flush (unit-level on the extracted cleanup);
      mark append + concurrent-flush safety (simulate interleaving).
- [ ] Manual smoke if an adb device is reachable (`adb devices`): 60s sample of any
      debuggable package; include output in report. If no device: say so honestly.
- [ ] Commit `feat(radar_native_host): overnight-robust sample + mark verbs`.

### Task C4: `capture` preflight, `diff`, `triage` verbs (radar_native_host)

**Files:** read `lib/src/capture/native_heap_capture.dart` (AdbHeapprofdCapture —
fixed-sleep startup flake) + existing profile parse/diff libs. Create
`lib/src/capture/capture_cli.dart` + `bin/` entries (`radar_capture`, `radar_diff`,
`radar_triage`); modify heapprofd capture for preflight.
**Behavior:**
- `radar_capture`: preflight BEFORE capture — heapprofd available (perfetto
  --query or API-level check via `getprop ro.build.version.sdk` ≥ 29), package
  profileable/debuggable (`dumpsys package` flags), then capture, then VALIDATE the
  pulled trace contains heap_profile rows (reuse the existing trace_processor seam;
  a 1KB-guard is not validation) — empty capture → exit 2 with the failed check
  named. Replace the fixed sleep with completion polling where the existing seam
  allows (read what's there; document what remains time-based).
- `radar_diff a.pftrace b.pftrace --format json|md` — existing diffNativeProfiles +
  the C1 toJson.
- `radar_triage session_dir/ [--format json|md]` — C1 triage() over the session
  timeline; md renders per-column verdict table + the router summary line first.
  `--compare other_session_dir/` — side-by-side per-column verdict+slope A vs B +
  a delta summary ("threads: +1.4/h → flat" — the before-fix vs after-fix loop).
- [ ] TDD: preflight matrix (old sdk / not profileable / empty trace) each → exit 2
      naming the check; diff json/md; triage md contract (summary first, columns
      table, not-measured listed); compare rendering incl. one column measured in A
      but not B (honest asymmetry, no fabricated delta).
- [ ] Commit `feat(radar_native_host): capture preflight + diff/triage/compare verbs`.

### Task C5: RadarTimeSeriesChart (radar_ui)

**Files:** read `lib/src/widgets/radar_trend_chart.dart` (Y-only painter — leave it)
+ tokens. Create `lib/src/widgets/radar_time_series_chart.dart` (+ painter file if
needed); barrel; pubspec minor bump + CHANGELOG.
**Interfaces — Produces:**
```dart
final class ChartSeries {
  final String label; final Color color;
  final List<({int tMicros, double value})> points;
  final List<({int startMicros, int endMicros})> gaps;   // rendered as breaks, never bridged
}
final class ChartMark { final int tMicros; final String label; }
final class ChartWindow { final int startMicros; final int endMicros; }  // shaded (settle)
class RadarTimeSeriesChart extends StatelessWidget {
  const RadarTimeSeriesChart({
    required List<ChartSeries> series, List<ChartMark> marks = const [],
    List<ChartWindow> shaded = const [], double? threshold,   // horizontal line
    String? yUnit, bool normalizePerSeries = false,           // multi-unit overlay
  });
}
```
Behavior: time axis with adaptive tick labels (s/m/h), legend (wraps), line breaks at
gaps, mark verticals with labels, shaded windows behind series, threshold line,
empty/single-point safe, dark-theme (the design system is dark-only — follow
SeverityTokens/colors.dart), width-safe at 320+ (no overflow ever; scrollable legend
if needed).
- [ ] TDD: golden-free widget tests (hit-test painters via CustomPaint semantics or
      pump+no-exception + key structural expectations: legend entries, mark labels,
      gap break count via painter inspection seam); width tests 320/722/1280;
      empty/single-point; normalize mode scales independently.
- [ ] Commit `feat(radar_ui): multi-series time chart (marks, gaps, shaded windows)`.

### Task C6: Device Monitor pane (radar_desktop) — import-first

**Files:** read `packages/radar_desktop/lib/src/app/desktop_view.dart` + rail +
`desktop_shell.dart` switch (ADDITIVE wiring; first-run-guide branch collision) +
how AndroidDetailScreen/native screens load files today (NativeTraceImporter seam)
+ `desktop_perf_call.dart`/connected-mode controller for the getMemoryUsage polling.
Create `lib/src/screens/device_monitor_screen.dart` (+ controller).
**Behavior:**
- Import a `session_dir/timeline.json` (C1 TriageTimeline) OR a radar_ci `run.json`
  (map its MetricSeries directly) → RadarTimeSeriesChart with marks, settle shading
  (AssessOptions.settle default), per-column TriageColumnAssessment chips (verdict +
  slope), router summary banner, batch-delta readout; session-vs-session compare
  (second file → side-by-side verdict/slope table — reuse C4's compare model if
  exported, else compute via triage()).
- Connected mode (existing desktop VM connection): poll getMemoryUsage per isolate —
  heapUsage and externalUsage as TWO separate ChartSeries (never merged), samples
  accumulated in-memory with gap on RPC failure; this is additive to the pane
  (live tab), NOT a replacement for import-first.
- DesktopView case + rail entry + switch case, additive.
- [ ] TDD: import both formats; malformed file → honest error panel; verdict chips
      match triage() output; compare table; live-poll controller with fake VmService
      (two series, gap on throw); ALL FOUR UI suites + width tests 800/722/1280.
- [ ] Commit `feat(radar_desktop): Device Monitor — import-first native/dart trends + verdicts`.

### Task C7: radar_ci --native co-drive + docs closeout

**Files:** radar_ci run_command/run_io (+pubspec: radar_native, radar_native_host);
docs/followups.md; READMEs (root, radar_ci, radar_native_host, radar_desktop).
**Behavior:**
- `radar_ci run --native-package com.example.app [--native-interval 10s]`: co-runs
  the C2 CompositeSampler alongside Dart sampling (host wall-clock, same run
  lifecycle incl. partial-flush + signals); run.json gains optional
  `nativeTimeline` (TriageTimeline JSON, schemaVersion additive-tolerant).
- `radar_ci gate`: native columns join the verdict gate (monotonicGrowth on any
  measured native column → exit 3) behind `--gate-native` (opt-in this release).
- `radar_ci report`: native per-column verdict table appended after the Dart series
  table (reuse C4's md rendering helpers via radar_native).
- Docs closeout: followups.md rewritten to current state (what shipped this train,
  what's deferred with pointers); README quick starts updated (CI front door +
  native lane one-liners: sample → triage → compare); CHANGELOGs for all bumped
  packages verified present.
- [ ] TDD: run doc round-trip with nativeTimeline; co-drive sampling with fake
      AdbRunner (gaps independent of Dart lane); gate matrix with --gate-native;
      report renders native table; old run.json (no nativeTimeline) parses.
- [ ] Commits: `feat(radar_ci): --native co-drive, gate + report integration`,
      `docs: refresh followups + quick starts for the attribution/CI/native train`.

## Verification gate (end of phase)
- [ ] All sub-PRs merged to integration; every package suite green; devtools chrome;
      desktop width tests.
- [ ] End-to-end local proof: radar_ci run --cmd (dart loop fixture) --native-package
      (if device present; else fake-runner integration test) → gate → report; attach
      report output to the final PR description.
- [ ] followups.md current; spec §5 marked implemented (with the import-first and
      --gate-native scoping notes).
