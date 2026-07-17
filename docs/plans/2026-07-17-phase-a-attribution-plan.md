# Phase A — Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Implementers MUST read the real files named in each task before coding — this plan
> pins contracts (names, signatures, semantics, tests); integration detail lives in the
> code you open.

**Goal:** Every leaked class is attributed to its owner (project / dependency /
framework / SDK); the post-diff default view groups by retaining anchor package with
the project group first; retaining paths highlight the hop where project code holds
the reference; leak clusters become visible with cross-session NEW/KNOWN/ACK/GONE
identity.

**Architecture:** Origin + anchor land in `leak_graph` (pure Dart, bump to 0.3.0),
surface through `radar_workbench` views (wired into BOTH hosts: DevTools `RadarView`
and desktop `DesktopView`), with palette/chips from `radar_ui` and runtime plumbing in
`flutter_leak_radar`. Spec: `docs/specs/2026-07-17-attribution-ci-native-design.md` §3.

**Tech stack:** pure Dart (leak_graph), Flutter (radar_ui, radar_workbench, hosts).
Toolchain: `~/development/flutter-latest/bin/flutter` (3.44.x = CI stable). Tests:
`dart test` for leak_graph; `flutter test` for radar_ui/workbench/desktop/runtime;
`flutter test --platform chrome` for flutter_leak_radar_devtools.

## Global constraints

- Worktree: `/Users/aiva6306/Projects/+Sandbox/-Projects/.radar-worktrees/attribution-ci-native`,
  branch `feat/attribution-ci-native`. Sub-branches per PR group below; PRs target
  `feat/attribution-ci-native`, never main.
- TDD per task: failing test → minimal implementation → pass → commit. Conventional
  commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`). No Claude attribution lines.
- **`pathSignature` and `GraphHop`/`GraphRetainingPath` `==`/`hashCode` must be
  byte-identical before/after this phase** (Phase B baselines key on signatures).
  Task A2's golden test is the tripwire; never weaken it.
- Honest degradation: heuristics must be labeled (report which package-detection
  source was used); a value that cannot be computed reads as absent, never as 0.
- Comment density: minimal, non-obvious only. Files < 800 lines. No `dart:io` in any
  library imported by radar_workbench views (web extension); io helpers only via the
  new `package:leak_graph/io.dart` entrypoint or host packages.
- After each task: run that package's full test suite + `dart analyze` (or
  `flutter analyze`) — zero new warnings.

## Sub-PR grouping (all target `feat/attribution-ci-native`)

| PR | Tasks | Branch |
|---|---|---|
| A-PR1 leak_graph 0.3.0 core | A1 A2 A3 A4 + ci constraint check | `feat/a1-leak-graph-origin` |
| A-PR2 runtime + passing fix | A5 A12 | `feat/a2-runtime-origin` |
| A-PR3 design tokens | A6 | `feat/a3-origin-tokens` |
| A-PR4 tables UX | A7 A8 | `feat/a4-grouped-tables` |
| A-PR5 paths UX + host sources | A9 | `feat/a5-anchor-paths` |
| A-PR6 clusters + identity | A10 A11 | `feat/a6-clusters-identity` |

---

### Task A1: ClassOrigin + OriginClassifier (leak_graph)

**Files:**
- Create: `packages/leak_graph/lib/src/analysis/class_origin.dart`
- Modify: `packages/leak_graph/lib/leak_graph.dart` (add export)
- Test: `packages/leak_graph/test/analysis/class_origin_test.dart`

**Interfaces — Produces:**
```dart
enum ClassOrigin { project, dependency, flutterFramework, dartSdk, unknown }

/// Framework packages (declaring-library classification).
const Set<String> kFlutterFrameworkPackages = {
  'flutter', 'flutter_test', 'flutter_localizations', 'flutter_driver',
  'flutter_web_plugins', 'sky_engine',
};

final class OriginClassifier {
  /// [projectPackages]: resolved app-owned package names (same semantics as
  /// GraphAnalysisOptions.appPackages after AppPackageSet resolution).
  const OriginClassifier({required Set<String> projectPackages});
  ClassOrigin classify(Uri libraryUri);
  /// Package name for `package:` URIs, 'dart:<lib>' for SDK, null otherwise.
  String? packageOf(Uri libraryUri);
}
```
Semantics: `dart:` scheme → dartSdk; `package:` first segment in
kFlutterFrameworkPackages → flutterFramework; in projectPackages → project; any other
`package:` → dependency; empty/other scheme (e.g. the analyzer's `Uri()` placeholder)
→ unknown.

- [ ] Failing tests: one per bucket + `Uri()`→unknown + `packageOf` cases
      (`package:foo/bar.dart`→`foo`, `dart:core`→`dart:core`, `Uri()`→null).
- [ ] Run: `cd packages/leak_graph && ~/development/flutter-latest/bin/dart test test/analysis/class_origin_test.dart` — FAIL.
- [ ] Implement `class_origin.dart`; export from barrel.
- [ ] Tests pass; `dart analyze` clean; full package suite green.
- [ ] Commit `feat(leak_graph): ClassOrigin taxonomy + OriginClassifier`.

### Task A2: Hop libraryUri + anchor plumb-through + golden signature (leak_graph)

**Files:**
- Modify: `packages/leak_graph/lib/src/model/graph_retaining_path.dart`,
  `packages/leak_graph/lib/src/model/graph_leak_cluster.dart`,
  `packages/leak_graph/lib/src/analysis/clustering.dart`,
  `packages/leak_graph/lib/src/analysis/graph_leak_analyzer.dart`
- Test: `packages/leak_graph/test/analysis/signature_stability_test.dart` (new),
  extend existing model/clustering/analyzer tests.

**Interfaces — Produces (deltas to real code you must read first):**
```dart
// GraphHop: + final Uri? libraryUri;  — in ctor, toJson ('libraryUri' string,
// omitted when null), fromJson (tolerant: absent→null).
// EXCLUDED from == and hashCode (equality stays structural: className/field/index).
// Document the exclusion in code: cluster identity must not shift with attribution.

// buildHops gains a 3rd PARALLEL list (same positional pairing rationale):
List<GraphHop> buildHops(List<PathLink> links, List<String> classNames,
    [List<Uri>? libraryUris]);

// LeakRecord: + final int? anchorHopIndex;  (index into path.hops of the
// attribution anchor; the analyzer already computes `anchorIndex` at
// graph_leak_analyzer.dart:188-196 and discards it — keep it.)

// GraphLeakCluster: + final String? leafClassName;  (internal leaf class when the
// headline is an anchored owner — clustering.dart:87 already headlines the anchor;
// preserve the leaf) + final int? anchorHopIndex;  Both in ==/hashCode/toJson/
// fromJson (tolerant fromJson: absent→null).
```
All 4 analyzer call sites of `buildHops` (graph_leak_analyzer.dart:61, 198, 461, 544)
pass the already-materialized library-uri list where one exists (`pathLibraries` at
:176-182); `retainingPathForClass` builds one the same way.

- [ ] **Golden signature test FIRST** (this is the phase tripwire):
```dart
test('pathSignature and hop equality ignore libraryUri', () {
  final hops = [
    GraphHop(className: 'MyBloc', field: '_subs'),
    GraphHop(className: '_List', index: 3),
    GraphHop(className: '_Closure'),
  ];
  expect(pathSignature(hops), 'MyBloc._subs>_List[]>_Closure');
  final withUri = GraphHop(className: 'MyBloc', field: '_subs',
      libraryUri: Uri.parse('package:app/bloc.dart'));
  expect(withUri, GraphHop(className: 'MyBloc', field: '_subs'));
  expect(withUri.hashCode, GraphHop(className: 'MyBloc', field: '_subs').hashCode);
  expect(pathSignature([withUri]), pathSignature([GraphHop(className: 'MyBloc', field: '_subs')]));
});
```
- [ ] More failing tests: GraphHop JSON round-trip with/without libraryUri; old JSON
      (no key) parses; cluster JSON round-trip with leafClassName/anchorHopIndex and
      without (back-compat); analyzer end-to-end on the existing in-memory fake graph
      asserts `LeakRecord.anchorHopIndex` matches the anchor position and the cluster
      carries `leafClassName` + `anchorHopIndex`.
- [ ] Run leak_graph suite — new tests FAIL, all 113 existing PASS.
- [ ] Implement; run full suite (existing tests must not change) + analyze.
- [ ] Commit `feat(leak_graph): hop-level libraryUri + serialized attribution anchor`.

### Task A3: PackageRollup + schemaVersion + detection source (leak_graph)

**Files:**
- Create: `packages/leak_graph/lib/src/model/package_rollup.dart`
- Modify: `packages/leak_graph/lib/src/model/graph_analysis_result.dart`,
  `packages/leak_graph/lib/src/analysis/graph_leak_analyzer.dart`, barrel export
- Test: `packages/leak_graph/test/model/package_rollup_test.dart`, extend analyzer tests

**Interfaces — Produces:**
```dart
enum AppPackageSource { explicitConfig, autoDetected, disabled }

final class PackageRollup {
  final String package;        // e.g. 'livekit_client', 'dart:core', '(unknown)'
  final ClassOrigin origin;
  final int classCount;        // distinct leaked classes attributed here
  final int instanceCount;
  final int shallowBytes;      // labeled shallow — never present as retained
  final int clusterCount;
  // + const ctor, ==/hashCode, toJson/fromJson
}

// GraphAnalysisResult additions (all optional, default const []/null — old JSON parses):
//   final List<PackageRollup> anchorRollups;    // grouped by attribution anchor pkg
//   final List<PackageRollup> declaredRollups;  // grouped by declaring library pkg
//   final AppPackageSource? appPackageSource;   // which detection source ran
//   toJson gains 'schemaVersion': 2 (int); fromJson tolerates absent (=1).
```
Rollup computation in `analyze()`: anchorRollups key = anchor package when
`attributionLibraryUri != null` else declaring package; declaredRollups key = the
record's own `libraryUri` package. Use `OriginClassifier.packageOf`; null → `(unknown)`.
`appPackageSource`: explicitConfig when `options.appPackages` non-empty, disabled when
`options.disableAppFilter`, else autoDetected.

- [ ] Failing tests: rollup JSON round-trip; analyzer produces both rollups on the fake
      graph (assert a dartSdk-declared leaf retained by a project anchor lands in the
      PROJECT anchor rollup and in the SDK declared rollup — the declared-vs-retained
      keystone); schemaVersion 2 written, absent tolerated; appPackageSource reported
      per options.
- [ ] Run — FAIL; implement; suite + analyze green.
- [ ] Commit `feat(leak_graph): per-package rollups, schemaVersion, detection source`.

### Task A4: io.dart entrypoint + version 0.3.0 (leak_graph) + CI constraint check

**Files:**
- Create: `packages/leak_graph/lib/io.dart`,
  `packages/leak_graph/lib/src/io/project_packages_io.dart`
- Modify: `packages/leak_graph/pubspec.yaml` (version 0.3.0),
  `packages/leak_graph/CHANGELOG.md`, `.github/workflows/ci.yaml`
- Test: `packages/leak_graph/test/io/project_packages_io_test.dart`

**Interfaces — Produces:**
```dart
// package:leak_graph/io.dart  (dart:io allowed HERE ONLY; main barrel untouched)
/// Workspace project packages: the root pubspec name + any workspace/melos member
/// package names found under [rootDir]. Returns {} (never throws) on missing files.
Future<Set<String>> projectPackagesFromDir(String rootDir);
/// Parse a pubspec.yaml string → package name (null if absent). Pure, testable.
String? packageNameFromPubspec(String pubspecYaml);
```
Implementation note: no new deps — the repo already resolves `yaml` transitively? DO
NOT assume: if `yaml` is not already a leak_graph dep, parse the `name:` line and
workspace member dirs with line-level parsing (a pubspec `name:` is a top-level
scalar; keep it dependency-free). Members: for each `packages/*/pubspec.yaml` under
rootDir plus rootDir's own pubspec.
- [ ] Failing tests with tmp-dir fixtures: root-only, root+members, missing dir → {}.
- [ ] Implement; suite + analyze green.
- [ ] CHANGELOG 0.3.0 entry (ClassOrigin, hop libraryUri, anchor serialization,
      rollups, io entrypoint; note: signatures unchanged).
- [ ] ci.yaml: add step `- name: Constraint sync check` / `run: ./tool/sync-constraints.sh --check`
      after the format check (read the script first; wire per its contract).
- [ ] Commit `feat(leak_graph): io entrypoint for project-package detection; 0.3.0`
      + `ci: wire sync-constraints --check`.
- [ ] Open A-PR1 → `feat/attribution-ci-native`.

### Task A5: Runtime origin + heapBytes (flutter_leak_radar)

**Files:**
- Modify: `packages/flutter_leak_radar/lib/src/analysis/leak_analyzer.dart`,
  `packages/flutter_leak_radar/lib/src/model/leak_finding.dart` (locate real paths —
  read `lib/` first), `packages/flutter_leak_radar/lib/src/engine/vm_heap_probe.dart`,
  `packages/flutter_leak_radar/lib/src/engine/leak_engine.dart`,
  pubspec (minor bump; leak_graph `^0.3.0`), CHANGELOG
- Test: extend the package's existing analyzer/engine/report tests

**Interfaces — Produces:**
```dart
// LeakFinding: + final ClassOrigin origin;      (re-export ClassOrigin from
//   flutter_leak_radar's barrel so app code doesn't import leak_graph directly)
//              + final int? bytes;               (shallow bytes for the finding's
//   class from its ClassSample.bytesCurrent — null when unavailable, NEVER 0)
// LeakReport: heapBytes actually populated (sum of current heap usage from the
//   probe when connected; null when not measured) +
//   final String projectPackageSource; // 'explicit' | 'rootLib' | 'autoDetected' | 'none'
```
Detection chain (spec §3.2): `LeakRadarConfig` explicit packages → probe
`getIsolate(main).rootLib.uri` package (one extra RPC on the existing `VmService`
connection at vm_heap_probe.dart:93-97; often unreachable on physical devices —
handle failure by falling through) → `AppPackageSet.autoDetect` → none. Wire the
resolved set into `GraphScan.appPackages` (kills the `const []` default) and stamp
`projectPackageSource` accordingly. `toJson`/`toMarkdown` include origin, bytes,
source.
- [ ] Failing tests: finding carries origin per classifier; bytes from ClassSample;
      absent → null (not 0); chain order incl. rootLib-failure fallback (fake probe);
      report JSON/markdown include the new fields + source label.
- [ ] Implement; `flutter test` + analyze green (use flutter-latest).
- [ ] Commit `feat(flutter_leak_radar): finding origin, bytes, project-package chain`.

### Task A12 (rides A-PR2): radarscope quick-menu fix

**Files:** Modify `packages/radarscope/lib/src/radar_overlay.dart` (~:223-230);
test in `packages/radarscope/test/`.
- [ ] Failing widget test: quick-menu "Open Performance" opens tab index 1 (today both
      callbacks are identical → opens Leaks).
- [ ] Fix (`initialTab: 1` equivalent — read the callback wiring); test green.
- [ ] Commit `fix(radarscope): quick-menu Open Performance opens the Performance tab`.
- [ ] Open A-PR2.

### Task A6: OriginTokens + chips (radar_ui)

**Files:**
- Create: `packages/radar_ui/lib/src/tokens/origin.dart`,
  `packages/radar_ui/lib/src/widgets/origin_chip.dart`,
  `packages/radar_ui/lib/src/widgets/triage_chip.dart`
- Modify: radar_ui barrel, pubspec (minor bump), CHANGELOG;
  `packages/radar_desktop/lib/src/.../module_palette.dart` (migrate semantics — read
  it first; keep NativeModuleKind API, re-point colors to OriginTokens meanings)
- Test: `packages/radar_ui/test/` token + chip tests; desktop palette test updates

**Interfaces — Produces:**
```dart
// radar_ui stays dependency-clean: its own display enum; workbench maps
// leak_graph ClassOrigin → RadarOrigin.
enum RadarOrigin { project, dependency, framework, sdk, unknown }
final class OriginTokens {
  // project = violet family (NOT accent green — accent means healthy/negative-delta
  // across the suite; native module palette migrates to agree: app/project=violet,
  // third-party/plugin=neutral-strong, system/framework=muted).
  static Color color(RadarOrigin origin);
  static String label(RadarOrigin origin); // 'yours' | 'dependency' | 'framework' | 'sdk' | '—'
}
class OriginChip extends StatelessWidget { const OriginChip({required RadarOrigin origin}); }
// Display-only enum owned by radar_ui ('fresh' avoids the `new` keyword). Workbench
// maps its persisted TriageStatus (A11) onto this — do NOT redefine this enum there.
enum TriageDisplay { fresh, known, acknowledged, gone }
class TriageChip extends StatelessWidget { const TriageChip({required TriageDisplay display}); }
// Rendered labels: NEW / KNOWN / ACK / GONE. GONE = positive (accent) — a fixed leak.
```
Follow the SeverityTokens template (`lib/src/tokens/severity.dart`) — the design
system is dark-only, so this is one fixed palette, not a light/dark pair.
- [ ] Failing tests: distinct colors per origin; project != accent; chip renders label;
      TriageChip GONE uses accent family; module_palette agreement test (app/project
      hue == OriginTokens project hue).
- [ ] Implement; `flutter test` radar_ui + radar_desktop palette tests green.
- [ ] Commit `feat(radar_ui): origin + triage tokens and chips; unify module palette`.
      Open A-PR3.

### Task A7: originOf + filters (radar_workbench)

**Files:**
- Modify: `packages/radar_workbench/lib/src/memory/mem_format.dart`,
  `packages/radar_workbench/lib/src/filter/filter_expression.dart` (~:455
  `_normalizeField`), pubspec (leak_graph `^0.3.0`)
- Test: extend mem_format + filter tests

**Interfaces — Produces:**
```dart
// mem_format.dart
RadarOrigin originOf(Uri? libraryUri, {required Set<String> projectPackages});
String? packageLabelOf(Uri? libraryUri); // 'livekit_client' | 'dart:core' | null
// FilterExpression new fields: `package:<name>` and `origin:<project|dependency|
// framework|sdk>` (alias `origin:yours` → project). Preset constant:
const String kHideFrameworkFilter = '!origin:framework !origin:sdk';
```
- [ ] Failing tests: originOf maps ClassOrigin→RadarOrigin buckets incl. null→unknown;
      filter parses/matches package: and origin: terms incl. negation; preset string
      round-trips through the parser.
- [ ] Implement; workbench suite + analyze green.
- [ ] Commit `feat(radar_workbench): origin helpers + package:/origin: filters`.

### Task A8: Grouped tables — the S1 default (radar_workbench)

**Files:**
- Create: `packages/radar_workbench/lib/src/memory/package_group_scaffold.dart`
- Modify: `packages/radar_workbench/lib/src/memory/class_histogram_view.dart`,
  `packages/radar_workbench/lib/src/memory/diff_table.dart`
- Test: widget tests for both views + scaffold

**Interfaces — Produces:**
```dart
/// Shared grouping presenter for histogram + diff rows.
final class PackageGroup<T> {
  final String package; final RadarOrigin origin;
  final List<T> rows; final int totalBytes; final int totalDelta;
}
List<PackageGroup<T>> groupRowsByPackage<T>(List<T> rows, {
  required Uri? Function(T) declaredLibraryOf,
  required Uri? Function(T) anchorLibraryOf, // may return declared when no anchor
  required int Function(T) bytesOf,
  required Set<String> projectPackages,
});
```
**S1 default state (contract, not preference):** after a diff loads, DiffTable renders
grouped by ANCHOR package; project group pinned first and expanded; dependency groups
collapsed showing rollup Δbytes; framework+sdk collapsed under one "runtime" group —
visible, never auto-hidden; within groups Δbytes desc. Flat mode remains a toggle;
"hide framework" is a preset chip (applies `kHideFrameworkFilter`), not a default.
Histogram: adds an origin chip + package label to rows (NO library column exists today
— budget the 34px row layout; truncate package label with tooltip) and the same
grouping toggle, default grouped. Group headers show "retained via" labeling for
anchor grouping and a `⚠ shallow bytes` affordance per spec honesty rule.
- [ ] Failing widget tests: default grouped state ordering (project first, expanded;
      runtime group collapsed but present); rollup deltas on collapsed headers; toggle
      to flat preserves sort; preset chip applies filter; histogram rows show chip.
- [ ] Implement; suite + analyze green (also run devtools ext tests
      `flutter test --platform chrome` — these views render there).
- [ ] Commit `feat(radar_workbench): anchor-package grouped histogram + diff (project-first default)`.
      Open A-PR4.

### Task A9: Anchor-highlighted paths + host project-package sources

**Files:**
- Modify: `packages/radar_workbench/lib/src/presentation/retaining_path_tile.dart`,
  class detail panel (read `lib/src/memory/` to locate), workbench session/settings
  controller for the override field;
  `packages/flutter_leak_radar_devtools/lib/` DTD store (projectRoots→pubspec read);
  `packages/radar_desktop/lib/` workspace controller (pubspec.lock/dir detect via
  `package:leak_graph/io.dart`) + anchor-hop open-in-editor
- Test: workbench widget tests; devtools chrome tests; desktop tests

**Interfaces — Produces:**
```dart
// Workbench host seam (core/, alongside RadarConnection — read the seam style):
abstract interface class ProjectContext {
  Future<Set<String>> projectPackages();          // may be empty (=unknown)
  String get sourceLabel;                          // 'workspace' | 'pubspec.lock' | 'manual' | 'none'
  Future<bool> openSource(Uri libraryUri) => Future.value(false); // desktop overrides
}
```
- Hop rows: colored left tick + OriginChip per hop (from `GraphHop.libraryUri`);
  anchor hop (index == cluster/record anchorHopIndex) gets highlighted treatment +
  "yours" marker; hop text `SelectableText`; a copy-path button copies the textual
  path (`Class.field > ...` + library URIs).
- Desktop `openSource`: resolve `package:` URI → file path via the workspace
  `package_config.json` when present; launch via existing external-tool seam (read
  `radar_native_host` ExternalTool/desktop Tools page pattern); graceful no-op+toast
  when unresolvable. DevTools: copy only.
- Both hosts expose a manual project-packages override (settings field) that trumps
  detection; UI shows `sourceLabel` (honesty rule).
- [ ] Failing tests: anchor hop highlighted; copy button emits full path; manual
      override wins and relabels source; desktop resolver maps package URI→path with
      a fixture package_config; unresolvable → false (no throw).
- [ ] Implement; workbench + devtools(chrome) + desktop suites green.
- [ ] Commit `feat(workbench,hosts): anchor-highlighted retaining paths + per-host project context`.
      Open A-PR5.

### Task A10: Leak-clusters view, wired into both hosts

**Files:**
- Create: `packages/radar_workbench/lib/src/memory/leak_clusters_view.dart`
- Modify: `packages/radar_workbench/lib/src/shell/radar_view.dart` (+ LeftRail +
  `_buildContent()` — read shell/), `packages/radar_desktop/lib/src/app/desktop_view.dart`
  + rail + `desktop_shell.dart` switch (KEEP WIRING ADDITIVE — first-run-guide WIP
  touches these files on another branch)
- Test: workbench widget tests + both host wiring tests

**Interfaces — Consumes:** `SnapshotBundle.analysisResult` (clusters now carry
attribution fields + rollups, stats.warnings). **Produces:** `RadarView.clusters` +
`DesktopView` case; `LeakClustersView(controller)` widget.
- Rows: cluster headline (anchor class), OriginChip, package, confidence badge,
  instances, shallow bytes, root kind; expand → representative path (A9 tile) +
  leafClassName when anchored. Ranking: confidence desc → project-anchor first →
  shallowBytes×instances. `stats.warnings` render in an alert strip at top (capture
  failures stop being invisible).
- [ ] Failing tests: ranking contract; warnings strip; empty state ("no clusters —
      N candidates suppressed" from stats); expansion shows path with anchor
      highlight; both hosts route to the view.
- [ ] Implement; all three packages' suites green (devtools via chrome).
- [ ] Commit `feat(workbench,hosts): leak clusters view with warnings + ranking`.

### Task A11: Cross-session identity (NEW / KNOWN / ACK / GONE)

**Files:**
- Create: `packages/radar_workbench/lib/src/session/triage_store.dart`
- Modify: `packages/radar_workbench/lib/src/session/snapshot_store.dart`
  (PersistedSession: actually check `version` on read; add triage map),
  `leak_clusters_view.dart`, `diff_table.dart` (chips)
- Test: session round-trip + view tests

**Interfaces — Produces:**
```dart
enum TriageStatus { fresh, known, acknowledged } // persisted; GONE is computed
final class TriageEntry {
  final String signature; final DateTime firstSeen;
  final TriageStatus status; final String? note;
  // ==/hashCode/toJson/fromJson
}
final class TriageStore { // lives inside PersistedSession JSON (schema addition)
  TriageEntry? entryFor(String signature);
  TriageStore upsert(TriageEntry entry);          // immutable — returns new store
  /// Chips for the current cluster list vs the store (radar_ui TriageDisplay):
  ///   no entry → fresh (NEW); entry+present → known/acknowledged; entry+absent → gone.
  Map<String, TriageDisplay> displayFor(Iterable<String> currentSignatures);
}
// TriageDisplay is radar_ui's enum (Task A6) — import it, do not redefine.
```
PersistedSession version: on read, `version > kSessionSchemaVersion` → refuse with a
clear message (forward-compat); `< current` → migrate (absent triage → empty store).
Views: clusters + diff rows show TriageChip; "since last session" toggle filters to
NEW+GONE; ACK action (with optional note) in the row menu; GONE section listed
separately at top when non-empty ("fixed since last session" — the payoff screen).
- [ ] Failing tests: displayFor all four states incl. GONE (entry present, signature
      absent); store JSON round-trip inside PersistedSession; version gate
      (higher→refuse, lower→migrate); toggle filters; ACK persists a note.
- [ ] Implement; suites green.
- [ ] Commit `feat(radar_workbench): cross-session leak identity (NEW/KNOWN/ACK/GONE)`.
      Open A-PR6.

---

## Verification gate (end of phase)

- [ ] All 6 sub-PRs merged into `feat/attribution-ci-native`; branch green:
      per-package `analyze` + full test suites incl. devtools `--platform chrome`.
- [ ] Golden signature test unchanged since A2 (diff the test file against A2's commit).
- [ ] Manual smoke on the example app (DevTools host): capture→act→capture → grouped
      diff project-first; clusters view shows anchors; hide-framework preset works.
- [ ] `dart format --output=none --set-exit-if-changed .` clean at repo root.
- [ ] Update `docs/followups.md` phase-A row; CHANGELOGs present for leak_graph,
      flutter_leak_radar, radar_ui, radarscope.
