# Phase B — Radar in CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development.
> Implementers read the real files named per task before coding; this plan pins
> contracts. Spec: `docs/specs/2026-07-17-attribution-ci-native-design.md` §4.

**Goal:** One command tracks a real app run's memory headlessly, a gate fails the
pipeline on honest verdicts with distinct exit codes, and the end-of-run report is
readable in 30 seconds.

**As-built inputs (already merged on `feat/attribution-ci-native`):**
- leak_graph 0.3.0 — `ClassOrigin`/`OriginClassifier`, `GraphHop.libraryUri`,
  `LeakRecord.anchorHopIndex`, `GraphLeakCluster.{leafClassName,anchorHopIndex,signature}`,
  `PackageRollup` (`anchorRollups`/`declaredRollups`), `resolvedAppPackages` (lands with
  Task A8), `AppPackageSource`, `schemaVersion: 2`, `package:leak_graph/io.dart`,
  `pathSignature` (byte-stable, golden-pinned).
- radar_trace 0.2.0 — `MetricSeries`/`MetricSample`/`SeriesGap`,
  `assessSeries(series, [AssessOptions])` → `SeriesAssessment`
  {monotonicGrowth, plateau, noisy, insufficientData} with slopePerHour/batchDeltaPerHour.
  **HARD CONSTRAINT: growth verdicts need ≥ ~12 assessed post-settle samples
  (Mann–Kendall floor; batch2 < 6 refuses). All cadence defaults below satisfy it.**

## Global constraints

- Same worktree/TDD/commit/toolchain rules as the Phase A plan (Global constraints
  section) — they bind every task here. Flutter/dart from `~/development/flutter-latest`.
- Exit-code contract everywhere: **0 ok / 1 usage error / 2 tool failure / 3 gate failed**.
- All new JSON stamped `schemaVersion`; readers treat NEWER major schema as
  tool-failure-style refusal, older/absent as legacy-tolerant.
- Honest degradation: unmeasured → absent/insufficientData, never 0/never a guess;
  baseline with older schemaVersion → "insufficient baseline", NEVER all-NEW.
- `pathSignature` stability tripwire (leak_graph signature_stability_test) must never
  be weakened; baselines key on it.

## Sub-PR grouping (target `feat/attribution-ci-native`)

| PR | Tasks | Branch |
|---|---|---|
| B-PR2 leak_graph CLI | B2 B3 | `feat/b2-leak-graph-cli` |
| B-PR3 radar_ci run | B4 | `feat/b3-radar-ci-run` |
| B-PR4 radar_ci gate+report | B5 | `feat/b4-radar-ci-gate` |
| B-PR5 CI dogfood + docs | B6 | `feat/b5-ci-dogfood` |

---

### Task B2: leak_graph CLI hardening (baseline, diff, thresholds, exit codes)

**Files:** read `packages/leak_graph/bin/` + `lib/src/cli/` first (cli_args.dart,
report_renderer.dart, existing analyze/leak_capture entrypoints), `histogram_diff.dart`.
- Modify: `packages/leak_graph/pubspec.yaml` (`executables:` gains `analyze`; alias
  `leak_analyze` if a bare `analyze` name collides on activation — decide, document),
  `lib/src/cli/cli_args.dart`, `bin/analyze.dart`
- Create: `lib/src/cli/baseline.dart`, `bin/diff.dart` (histogram diff CLI),
  `lib/src/model/` addition ONLY if ClassCountDiff needs toJson (it does)
- Test: cli + baseline unit tests (pure, no process spawning; test the command
  functions, not the bin shims — follow how existing CLI code is factored/tested)

**Interfaces — Produces:**
```dart
// baseline.dart
final class LeakBaseline {
  final int schemaVersion;                 // 1
  final DateTime createdAt;
  final Map<String, BaselineCluster> clustersBySignature;
  // toJson/fromJson (tolerant)
}
final class BaselineCluster { final String signature; final String className;
  final int instanceCount; final int retainedShallowBytes; /* json */ }

enum ClusterNovelty { newCluster, known, grown }
final class BaselineComparison {
  final List<ClusterDelta> deltas;         // one per current cluster
  final List<BaselineCluster> gone;        // in baseline, absent now
}
final class ClusterDelta {
  final GraphLeakCluster cluster; final ClusterNovelty novelty;
  final int instanceDelta; final int bytesDelta;
  final String? nearestKnownSignature;     // for newCluster: closest baseline
                                           // signature (see below), else null
}
BaselineComparison compareToBaseline(GraphAnalysisResult current, LeakBaseline baseline);
// nearestKnownSignature: cheapest honest metric — highest shared-hop-token overlap
// (split signatures on '>'; Jaccard over token multisets); ties → lexicographic;
// only report when overlap ≥ 0.5, else null. Pure function, unit-tested.

// Gate evaluation (shared by analyze CLI now and radar_ci later — keep pure):
final class GateOptions {
  final int? maxNewClusters;               // null = not gated
  final int? maxTotalClusters;
  final int? maxClassGrowthInstances;      // vs baseline, any known cluster
  final int? maxHeapGrowthBytes;           // vs baseline total shallow bytes
  final LeakConfidence minConfidence;      // gate only counts clusters at/above
}
final class GateResult { final bool passed; final List<String> violations; }
GateResult evaluateGate(BaselineComparison cmp, GateOptions opts);
```
CLI flags on `analyze`: `--baseline <file>`, `--write-baseline <file>`,
`--fail-on-new-clusters` / `--max-new-clusters N` / `--max-heap-growth-bytes N` /
`--min-confidence <heuristic|probable|confirmed>` (map onto GateOptions), exit 3 when
gate fails, 2 on unreadable snapshot/baseline-io errors, 1 on bad flags. Older/newer
baseline schemaVersion → prints "baseline not comparable (schemaVersion X)" and the
gate treats baseline as ABSENT (never all-NEW). `diff` bin: two snapshot files (or two
analysis JSONs — read what bin/analyze consumes today and accept the same inputs) →
ClassCountDiff JSON (+toJson added) or text.

- [ ] TDD: baseline round-trip; novelty classification (new/known/grown); gone list;
      nearest-known (overlap ≥0.5 hit, <0.5 → null, tie-break); gate each threshold
      independently + combined; schemaVersion mismatch → baseline-absent behavior;
      exit-code mapping tests at the command-function level.
- [ ] Existing CLI behavior unchanged when no new flags passed (regression: current
      analyze text output byte-stable on a fixture).
- [ ] Commits: `feat(leak_graph): baseline compare + gate evaluation for CI`,
      `feat(leak_graph): diff CLI + ClassCountDiff serialization`.

### Task B3: renderers — the 30-second report (md/github)

**Files:** read `lib/src/cli/report_renderer.dart` (40-line plain text — keep it).
- Create: `lib/src/cli/markdown_renderer.dart`
- Modify: `bin/analyze.dart` (`--format text|json|md|github`), barrel if needed
- Test: renderer golden-ish tests (string assertions on structure, not full goldens)

**Interfaces — Produces:**
```dart
String renderMarkdownReport(GraphAnalysisResult result, {
  BaselineComparison? comparison, GateResult? gate,
  required bool github,              // github: step-summary/PR-comment tuning
});
```
**30-second contract (test-pinned):** line 1 = verdict (`✅ no leak clusters` /
`❌ gate failed: <first violation>` / `⚠ N clusters (no gate)`); then AT MOST 3
NEW-or-worst project-anchor clusters, each rendered as: cluster headline class,
package + OriginChip-equivalent label `[yours]`/`[dependency]`/…, instance/byte
figures (labeled shallow), the ANCHOR HOP line ("your code holds it at
`GroupCallBloc._subs`" — from anchorHopIndex over representativePath), and for
newCluster the nearest-known line when present. Everything else (full cluster table,
rollup tables by anchor + declared, stats/warnings, gone-clusters list) inside
`<details>` blocks. Plain `md` = same without GitHub-specific syntax beyond standard
markdown. Package rollup tables show anchor rollups first ("retained via"), declared
second.
- [ ] TDD: verdict-line variants; ≤3 rule; anchor-hop line renders from a fixture
      cluster with anchorHopIndex; nearest-known line; details sections present;
      no unlabeled byte figures (grep test asserts "shallow" qualifier appears).
- [ ] Commit: `feat(leak_graph): markdown/github renderers with 30-second contract`.

### Task B4: radar_ci package + `run`

**Files:**
- Create: `packages/radar_ci/` — pubspec (`publish_to: none`, deps: args, vm_service,
  leak_graph (path-resolved via workspace), radar_trace, radar_native_host (URI
  discovery reuse), meta), `bin/radar_ci.dart` (verb dispatcher), `lib/src/run/`
  (attach.dart, sampler.dart, checkpoint.dart, run_command.dart), `lib/src/model/run_document.dart`,
  README.md stub. Add to root workspace `pubspec.yaml` members + melos if globbed +
  `.github/workflows/ci.yaml` analyze/test steps (mirror existing pure-Dart entries).
- Test: fake-VmService unit tests for sampler/checkpoint/run; attach-parser tests.

**Interfaces — Produces:**
```dart
// run_document.dart — THE interchange artifact (schemaVersion 1)
final class RadarRunDocument {
  final int schemaVersion;                 // 1
  final RunMetadata metadata;              // startedAt, flutterVersion?, dartVersion?,
                                           // targetPlatform?, mode?, cmdLine?, notes
  final List<MetricSeries> series;         // radar_trace type, one per metric:
    // 'dart.heap.used', 'dart.heap.capacity', 'dart.external' (per-isolate summed),
    // 'process.rss' (getProcessMemoryUsage), gaps recorded on RPC failure
  final List<RunCheckpoint> checkpoints;
  // toJson/fromJson tolerant
}
final class RunCheckpoint {
  final int tMicros; final String label;   // 'start','cp1',...,'end' or user --mark
  final Map<String, int> allocationTopN;   // className -> instancesCurrent (top N by size)
  final String? snapshotPath;              // full heap snapshot file when taken
  final String? analysisPath;              // GraphAnalysisResult JSON when analyzed
}
```
`radar_ci run` flags + defaults (defaults MUST satisfy the ≥12-sample floor):
`--vm-uri ws://…` OR `--cmd "flutter run --profile -d …"` (spawn, parse `--machine`
JSON app.debugPort/vmServiceUri events; fall back to the AndroidVmServiceDiscovery
logcat regex — REUSE `parseLogcatVmServiceUris` from radar_native_host, do not
re-implement); `--duration 3m` (min enforced 2m unless `--allow-short`),
`--sample-interval 5s`, `--settle 30s`, `--checkpoints 3` (evenly spaced, plus
start/end), `--snapshot-every 1` (full snapshot every Nth checkpoint; 0 = none),
`--exec "cmd"` / `--call-extension ext.name` (driver hook fired between checkpoints),
`--out run.json`, `--project-packages a,b` (else leak_graph io.dart detection from
cwd, source stamped in metadata). Analysis of captured snapshots runs in-process via
leak_graph (`GraphAnalysisOptions(appPackages: resolved)`), writing analysis JSON next
to run.json. RPC failure during sampling → SeriesGap with reason, run continues;
spawn/attach failure → exit 2 with a clear message.
- [ ] TDD with a fake VmService (follow flutter_leak_radar's fake-probe patterns):
      series built with correct names/units; gap on RPC throw; checkpoint cadence math
      (N evenly spaced incl start/end); defaults produce ≥12 post-settle samples
      (assert arithmetic in a test); run.json round-trip; machine-JSON URI parsing +
      logcat fallback parsing (fixture strings); driver hook invocation order.
- [ ] Manual smoke REQUIRED before commit: write a 20-line allocate-in-a-loop script
      in /tmp, launch it with `dart --enable-vm-service=0 /tmp/loop.dart`, parse the
      "The Dart VM service is listening on …" stdout URI (add this plain-dart pattern
      to the same parser used for flutter --machine; note it in the report), attach,
      and produce a real run.json; include the series sample counts in the report.
- [ ] Commit: `feat(radar_ci): run — attach/spawn, sampled series, checkpoints, run.json`.

### Task B5: radar_ci `gate` + `report`

**Files:** Create `packages/radar_ci/lib/src/gate/gate_command.dart`,
`lib/src/report/report_command.dart`; extend `bin/radar_ci.dart`.
- Test: unit tests over fixture RadarRunDocuments (synthesized in-memory, tiny).

**Behavior:**
- `gate run.json [--baseline base.json ...]`: DEFAULT mode = verdict-based:
  exit 3 iff (a) any `assessSeries` verdict on 'dart.heap.used'/'dart.external'/
  'process.rss' is monotonicGrowth, OR (b) baseline comparison (leak_graph
  compareToBaseline over the last checkpoint's analysis) yields NEW project-anchor
  clusters at ≥ minConfidence. Byte-absolute flags (reuse GateOptions) are opt-in
  additions. insufficientData/noisy NEVER fail the gate (print as not-assessed).
  `--write-baseline` from the last analysis. Prints one verdict line per gated signal.
- `report run.json [--baseline …] --format md|github|json [--out file]`: merges
  series assessments (one line per metric: verdict + slope) with the leak_graph
  markdown renderer output for the last checkpoint's analysis (REUSE
  renderMarkdownReport — single rendering path). json = the run document + assessments
  + comparison in one envelope (schemaVersion 1). The 30-second contract governs the
  top of md/github output: line 1 overall verdict (worst of series+gate), then the
  ≤3 clusters, series table next, details after.
- [ ] TDD: verdict-based gate matrix (growth→3, plateau/noisy/insufficient→0,
      NEW-project-cluster→3, known-only→0, baseline-schema-mismatch→0 with honest
      note); report md structure incl. series table + reuse of leak_graph renderer;
      json envelope round-trip; exit codes.
- [ ] Commit: `feat(radar_ci): verdict-based gate + unified report`.

### Task B6: hermetic e2e + CI dogfood + adoption front door

**Files:**
- Create: `packages/radar_ci/test_fixtures/leaky_app.dart` + `healthy_app.dart`
  (pure-Dart scripts: leaky = grows a static List<List<int>> every 100ms and holds it —
  a planted monotonic leak; healthy = same allocation churn but released — plateau),
  `packages/radar_ci/test/e2e_gate_test.dart` (spawns `dart --enable-vm-service=0`
  on each fixture via Process.start, parses the URI from stdout, runs the IN-PROCESS
  run+gate command functions with short-window options (--allow-short, sample 250ms,
  duration 20s, settle 2s → ≥40 samples, MK floor satisfied), asserts gate exit 3 on
  leaky / 0 on healthy; SKIPS with a clear message when Process spawning is
  unavailable; tagged so CI runs it explicitly).
- Create: `examples/ci/memory.yaml` (template: two-lane doc — main-branch baseline
  artifact publish + PR fetch-and-compare, AND two-run-compare alternative; step
  summary + artifact upload snippets; honest comments about runner variance).
- Modify: `.github/workflows/ci.yaml` — radar_ci analyze/test steps + a dedicated
  `memory-selftest` job: runs the e2e gate test, then runs `report` on the produced
  run.json and appends md output to `$GITHUB_STEP_SUMMARY`, uploads run.json artifact.
- Modify: repo `README.md` — "Radar in CI" quick-start section (the front door):
  the one-command local flow `dart run radar_ci run --cmd "flutter run --profile"`,
  the gate exit-code contract, the ≥12-samples cadence note, link to examples/ci.
- Modify: `example/lib/` — add a `ext.radarscope.selftest` service-extension driver
  (read how the example app registers extensions; reuse runLeakSelfTest) so
  `radar_ci run --call-extension` has a real target; document in example README.
- [ ] e2e test proves the FULL pipeline in CI (attach → sample → verdict → exit code).
      Verify locally first: run the e2e test file, include output in report.
- [ ] Commits: `feat(radar_ci): hermetic planted-leak e2e gate test`,
      `ci: memory selftest job + step-summary report demo`,
      `docs: Radar-in-CI front door + baseline lifecycle template`.

## Verification gate (end of phase)
- [ ] All sub-PRs merged to integration; branch green per-package (analyze+test).
- [ ] e2e gate test passes locally AND in the repo CI run.
- [ ] `dart run radar_ci run --cmd` smoke against the example app on a local device/
      simulator if available; else the dart-script smoke from B4 re-verified.
- [ ] followups.md updated; radar_ci README complete.
