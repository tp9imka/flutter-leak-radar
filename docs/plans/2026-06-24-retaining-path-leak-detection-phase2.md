# Retaining-Path Leak Detection — Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add **live-tree reachability** to the `leak_graph` core (confirm/suppress candidates) and wire the analyzer into `flutter_leak_radar` so it runs **live on-device every Nth navigation**, surfacing confirmed retaining-path leaks as findings.

**Architecture:** Phase 1 shipped the offline + denylist analyzer. Phase 2 adds (A) a pure-Dart `LiveTreeReachability` pass in `leak_graph` that BFS-marks objects reachable from the live UI-tree anchor, so a denylist candidate that is NOT live-reachable becomes a *confirmed* leak; and (B) a `flutter_leak_radar` integration that acquires a `HeapSnapshotGraph` live (via the existing VM-service connection), runs `GraphLeakAnalyzer` with reachability on, and maps clusters to `LeakFinding`s under a new `LeakKind.retainedByNonLiveRoot`.

**Tech Stack:** Dart (`leak_graph`, pure Dart + `vm_service`), Flutter (`flutter_leak_radar`), the merged Phase 1 `leak_graph` core.

Spec: `docs/specs/2026-06-24-retaining-path-leak-detection-design.md`. Phase 1 plan: `docs/plans/2026-06-24-retaining-path-leak-detection-phase1.md`.

## Global Constraints

- `leak_graph` core stays **pure Dart — no Flutter** (only `vm_service`, `args`, `meta`). Live-tree anchors are matched by **class name string**, never via Flutter APIs.
- Runtime graph analysis is **opt-in** (`GraphScan` config null = off), **debug/profile only, full release no-op, never-throw** (`runSafelyAsync`), and **size-guarded** (skip when heap > `maxGraphObjects`).
- Reuse the existing `LeakFinding`/`RetainingPathView`; **no freezed** (hand-rolled immutable + manual `==`/`hashCode`); **honest degradation** — `LeakConfidence.confirmed` only when a live anchor was found, else `heuristic`; never fabricate a finding.
- Phase 1 behavior must not regress: reachability is **opt-in via `GraphAnalysisOptions.confirmWithReachability` (default `false`)**, so existing Phase 1 tests/CLI are unchanged.
- `flutter_leak_radar` gains a dependency on `leak_graph` (resolved via the pub workspace for dev; before publishing, pin a version dep — out of scope here). Bump `flutter_leak_radar` `0.0.2 → 0.1.0`.
- Minimal comments. CI gates `dart format` — run it before each commit.

## File Structure

```
packages/leak_graph/
  lib/src/analysis/live_tree.dart            # NEW — LiveTreeReachability (BFS from anchor)
  lib/src/analysis/graph_leak_analyzer.dart  # MODIFY — confirmWithReachability + confidence + suppression
  lib/src/analysis/clustering.dart           # MODIFY — clusterLeaks gains a confidence param
  lib/src/cli/cli_args.dart + report_renderer.dart + bin/analyze.dart  # MODIFY — --confirm flag
packages/flutter_leak_radar/
  pubspec.yaml                               # MODIFY — add leak_graph dep; version 0.1.0
  lib/src/model/leak_kind.dart               # MODIFY — add retainedByNonLiveRoot
  lib/src/config/graph_scan.dart             # NEW — GraphScan config
  lib/src/config/leak_radar_config.dart      # MODIFY — graphScan field + standard() param
  lib/src/engine/heap_graph_source.dart      # NEW — acquire HeapSnapshotGraph (live + fallback) → HeapGraphView
  lib/src/engine/graph_finding_mapper.dart   # NEW — GraphLeakCluster → LeakFinding (+ RetainingPathView)
  lib/src/engine/leak_engine.dart            # MODIFY — every-Nth-nav graph scan + merge findings
  lib/src/ui/leak_radar_screen.dart / finding_detail_screen.dart  # MODIFY — label the new kind
  example/lib/main.dart                      # MODIFY — enable GraphScan to demo
```

---

### Task 1: `LiveTreeReachability` (leak_graph core)

**Files:**
- Create: `packages/leak_graph/lib/src/analysis/live_tree.dart`
- Modify: `packages/leak_graph/lib/leak_graph.dart` (export)
- Test: `packages/leak_graph/test/analysis/live_tree_test.dart`

**Interfaces:**
- Consumes: `HeapGraphView` (`rootId`, `nodeCount`, `node(id)` → `HeapNode{className, edges}`), `InMemoryHeapGraph` test double.
- Produces:
  - `class LiveTreeReachability { factory LiveTreeReachability.compute(HeapGraphView graph, {Set<String>? anchorClassNames}); bool get hasAnchor; bool isReachable(int nodeId); }`
  - `const Set<String> kDefaultLiveAnchorClassNames` = `{'WidgetsFlutterBinding', 'WidgetsBinding', 'RenderView', '_ReusableRenderView', 'RootWidget', 'RootElement', 'RenderObjectToWidgetElement'}`.

`compute`: scan all nodes for any whose `className` ∈ `anchorClassNames` (default `kDefaultLiveAnchorClassNames`) → these are anchors. If none, `hasAnchor = false` and `isReachable` returns `false` for all. Else BFS (iterative) from every anchor node over `node(id).edges` → a reachable-id set; `isReachable(id)` = id in set. Node enumeration uses `0..nodeCount-1` with a guard (matches the analyzer's contract).

- [ ] **Step 1: Write failing tests** `live_tree_test.dart`:
```dart
import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';
import '../support/in_memory_heap_graph.dart';

HeapNode n(int id, String cls, List<int> targets) => HeapNode(
    id: id, className: cls, libraryUri: Uri.parse('package:app/a.dart'),
    shallowSize: 8, edges: [for (final t in targets) HeapEdge(targetId: t)]);

void main() {
  test('no anchor -> hasAnchor false, nothing reachable', () {
    final g = InMemoryHeapGraph.of({0: n(0,'Root',[1]), 1: n(1,'Foo',[])});
    final r = LiveTreeReachability.compute(g);
    expect(r.hasAnchor, isFalse);
    expect(r.isReachable(1), isFalse);
  });

  test('marks nodes reachable from a WidgetsBinding anchor', () {
    // 0(Root) -> 1(WidgetsFlutterBinding) -> 2(HomeState); and 0 -> 3(Leaked)
    final g = InMemoryHeapGraph.of({
      0: n(0,'Root',[1,3]), 1: n(1,'WidgetsFlutterBinding',[2]),
      2: n(2,'HomeState',[]), 3: n(3,'Leaked',[]),
    });
    final r = LiveTreeReachability.compute(g);
    expect(r.hasAnchor, isTrue);
    expect(r.isReachable(2), isTrue);   // under the live tree
    expect(r.isReachable(3), isFalse);  // not under the live tree
  });
}
```

- [ ] **Step 2: Run** `cd packages/leak_graph && dart test test/analysis/live_tree_test.dart` → FAIL (undefined).
- [ ] **Step 3: Implement** `live_tree.dart` per the Interfaces block (iterative BFS, anchor-by-name).
- [ ] **Step 4: Run** → PASS. `dart analyze` clean. `dart format .`.
- [ ] **Step 5: Commit** `feat(leak_graph): LiveTreeReachability (BFS from UI-tree anchor)`.

---

### Task 2: Wire reachability into `GraphLeakAnalyzer`

**Files:**
- Modify: `packages/leak_graph/lib/src/analysis/graph_leak_analyzer.dart`, `packages/leak_graph/lib/src/analysis/clustering.dart`
- Test: `packages/leak_graph/test/analysis/graph_leak_analyzer_test.dart` (extend)

**Interfaces:**
- Consumes: `LiveTreeReachability` (Task 1), existing `GraphLeakAnalyzer`/`GraphAnalysisOptions`/`clusterLeaks`.
- Produces:
  - `GraphAnalysisOptions` gains `final bool confirmWithReachability;` (default `false`) and `final Set<String>? liveAnchorClassNames;` (default null → `kDefaultLiveAnchorClassNames`).
  - `clusterLeaks(List<LeakRecord>, {int minClusterSize, LeakConfidence confidence})` — new `confidence` param (default `LeakConfidence.heuristic`); the emitted `GraphLeakCluster.confidence` uses it.
  - `GraphAnalysisStats` gains `final int suppressedByLiveTree;`.

Algorithm change in `analyze`: after collecting leak-prone `LeakRecord`s and BEFORE clustering, if `options.confirmWithReachability`: compute `LiveTreeReachability.compute(graph, anchorClassNames: options.liveAnchorClassNames)`. If `hasAnchor`: drop every `LeakRecord` whose terminal node id `isReachable` (count into `suppressedByLiveTree`); cluster the survivors with `confidence: LeakConfidence.confirmed`. If `!hasAnchor`: no suppression, cluster with `confidence: heuristic` (degraded). When `confirmWithReachability` is false: unchanged Phase 1 path (heuristic, no suppression, `suppressedByLiveTree: 0`).

- [ ] **Step 1: Write failing test** (add to `graph_leak_analyzer_test.dart`):
```dart
test('reachability suppresses a live-reachable candidate and confirms the rest', () {
  // 0(Root) -> 1(WidgetsFlutterBinding) -> 2(_LeakyState app, also under live tree)
  // 0 -> 3(_Timer) -> 4(_LeakyState app, NOT under live tree)
  // With confirmWithReachability: node 4 is a CONFIRMED leak; node 2 is suppressed.
  // Assert: one cluster, className '_LeakyState', confidence == LeakConfidence.confirmed,
  // stats.suppressedByLiveTree == 1.
});
test('no live anchor -> degrades to heuristic, no suppression', () { /* graph w/o binding */ });
```
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the option, the `clusterLeaks` confidence param, and the reachability step in `analyze`.
- [ ] **Step 4: Run** full package suite `dart test` → all PASS (Phase 1 tests unchanged since default is false). `dart analyze` clean. `dart format .`.
- [ ] **Step 5: Commit** `feat(leak_graph): reachability confirm/suppress in GraphLeakAnalyzer`.

---

### Task 3: CLI `--confirm` flag

**Files:**
- Modify: `packages/leak_graph/lib/src/cli/cli_args.dart`, `bin/analyze.dart`, `report_renderer.dart`
- Test: `packages/leak_graph/test/cli/cli_args_test.dart` (extend)

**Interfaces:**
- `CliConfig` gains `final bool confirm;`; `parseCliArgs` adds a `--confirm` flag (default false). `bin/analyze.dart` maps it to `GraphAnalysisOptions(confirmWithReachability: c.confirm, …)`. `renderReport` prints each cluster's `confidence` (`confirmed`/`heuristic`).

- [ ] **Step 1: Write failing tests** — `parseCliArgs(['d.data','--confirm']).confirm == true`; default false; `renderReport` includes the confidence label.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS. analyze + format clean.
- [ ] **Step 5: Commit** `feat(leak_graph): CLI --confirm (reachability) + confidence in report`.

---

### Task 4: `LeakKind.retainedByNonLiveRoot` (runtime)

**Files:**
- Modify: `packages/flutter_leak_radar/lib/src/model/leak_kind.dart`
- Test: `packages/flutter_leak_radar/test/model/leak_kind_test.dart` (create if absent)

**Interfaces:**
- Produces: `LeakKind.retainedByNonLiveRoot` enum value (add to the existing `enum LeakKind { notDisposed, notGced, gcedLate, growth, retainedByNonLiveRoot }`). Any `switch`/label maps over `LeakKind` must handle it.

- [ ] **Step 1: Write failing test** asserting `LeakKind.values` contains `retainedByNonLiveRoot` and any kind→label helper returns a non-empty label for it.
- [ ] **Step 2: Run** `cd packages/flutter_leak_radar && flutter test test/model/leak_kind_test.dart` → FAIL.
- [ ] **Step 3: Implement** — add the enum value; update any exhaustive `switch` on `LeakKind` (search `LeakKind.` usages) to handle it.
- [ ] **Step 4: Run** → PASS. `flutter analyze` clean.
- [ ] **Step 5: Commit** `feat(flutter_leak_radar): LeakKind.retainedByNonLiveRoot`.

---

### Task 5: `GraphScan` config + `LeakRadarConfig` integration

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/config/graph_scan.dart`
- Modify: `packages/flutter_leak_radar/lib/src/config/leak_radar_config.dart`
- Test: `packages/flutter_leak_radar/test/config/graph_scan_test.dart`, extend `leak_radar_config_test.dart`

**Interfaces:**
- Produces:
  - `final class GraphScan { const GraphScan({this.everyNthNavigation = 5, this.maxGraphObjects = 500000, this.appPackages = const [], this.minClusterSize = 2}); final int everyNthNavigation; final int maxGraphObjects; final List<String> appPackages; final int minClusterSize; }` with `==`/`hashCode`.
  - `LeakRadarConfig` gains `final GraphScan? graphScan;` (default `null` = disabled), in the const ctor, `copyWith`, `==`/`hashCode`; `LeakRadarConfig.standard({… GraphScan? graphScan})` forwards it.

- [ ] **Step 1: Write failing tests** — `GraphScan` defaults + equality; `standard(graphScan: GraphScan())` sets it; configs differing only by `graphScan` are unequal.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS. analyze clean.
- [ ] **Step 5: Commit** `feat(flutter_leak_radar): GraphScan config`.

---

### Task 6: `leak_graph` dependency + `HeapGraphSource` acquisition

**Files:**
- Modify: `packages/flutter_leak_radar/pubspec.yaml` (add `leak_graph` dependency; bump version to `0.1.0`)
- Create: `packages/flutter_leak_radar/lib/src/engine/heap_graph_source.dart`
- Test: `packages/flutter_leak_radar/test/engine/heap_graph_source_test.dart`

**Interfaces:**
- Consumes: `package:leak_graph` (`HeapGraphView`, `VmSnapshotGraphView`, `heapGraphFromBytes`), `package:vm_service` (`HeapSnapshotGraph.getSnapshot`), the existing `writeHeapSnapshotFile()` + VM connection in `VmHeapProbe`.
- Produces: `abstract interface class HeapGraphSource { Future<HeapGraphView?> acquire({required int maxObjects}); }` and `final class VmHeapGraphSource implements HeapGraphSource` that: (1) tries `HeapSnapshotGraph.getSnapshot(service, isolate, calculateReferrers: false, decodeIdentityHashCodes: false)` via the live connection; (2) falls back to `writeHeapSnapshotFile()` → read bytes → `heapGraphFromBytes`; wraps in `VmSnapshotGraphView`; returns `null` (never throws) when unavailable or `objects.length > maxObjects`.

- [ ] **Step 1: Write failing test** with a `FakeHeapGraphSource` returning an `InMemoryHeapGraph`, asserting `acquire` returns it and that a size-over-limit source returns `null`. (The real `VmHeapGraphSource` is validated on-device; here test the interface + size guard via a fake, like the Phase-1 probe tests.)
- [ ] **Step 2: Run** `flutter test test/engine/heap_graph_source_test.dart` → FAIL.
- [ ] **Step 3: Implement** the interface + `VmHeapGraphSource`. Add `leak_graph` to pubspec deps; bump version `0.1.0`; `flutter pub get`.
- [ ] **Step 4: Run** → PASS. analyze clean.
- [ ] **Step 5: Commit** `feat(flutter_leak_radar): leak_graph dep + HeapGraphSource (live + file fallback)`.

---

### Task 7: `GraphLeakCluster` → `LeakFinding` mapper

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/engine/graph_finding_mapper.dart`
- Test: `packages/flutter_leak_radar/test/engine/graph_finding_mapper_test.dart`

**Interfaces:**
- Consumes: `GraphLeakCluster`, `GraphRetainingPath`, `GraphHop`, `RootKind`, `LeakConfidence` (from `leak_graph`); `LeakFinding`, `LeakKind`, `LeakSeverity`, `RetainingPathView`, `RetainingHop` (runtime).
- Produces: `LeakFinding mapGraphCluster(GraphLeakCluster c)` → `LeakFinding(className: c.className, kind: LeakKind.retainedByNonLiveRoot, severity: _severity(c), liveCount: c.instanceCount, growth: 0, library: c.libraryUri?.toString(), tag: c.rootKind.label, retainingPath: _mapPath(c.representativePath))`. `_severity`: `confirmed` + instanceCount ≥ 2 → `critical`, else `warning`. `_mapPath`: `GraphRetainingPath.hops` → `RetainingPathView(gcRootType: rootKind.label, elements: hops.map((h) => RetainingHop(objectType: h.className, field: h.field, index: h.index)))`.

- [ ] **Step 1: Write failing test** — build a `GraphLeakCluster` (className `_LeakyState`, instanceCount 3, rootKind timer, confidence confirmed, a 2-hop path), assert the mapped `LeakFinding` has `kind == retainedByNonLiveRoot`, `liveCount == 3`, `severity == critical`, `tag == 'Timer'`, and a `retainingPath` with the right hop objectTypes.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS. analyze clean.
- [ ] **Step 5: Commit** `feat(flutter_leak_radar): map GraphLeakCluster → LeakFinding`.

---

### Task 8: Every-Nth-navigation graph scan in `LeakEngine`

**Files:**
- Modify: `packages/flutter_leak_radar/lib/src/engine/leak_engine.dart`, `packages/flutter_leak_radar/lib/src/leak_radar.dart` (manual trigger facade)
- Test: `packages/flutter_leak_radar/test/engine/graph_scan_test.dart`

**Interfaces:**
- Consumes: `GraphScan` (Task 5), `HeapGraphSource` (Task 6), `mapGraphCluster` (Task 7), `GraphLeakAnalyzer`/`GraphAnalysisOptions` (`confirmWithReachability: true`) from `leak_graph`.
- Produces: `LeakEngine` takes an optional `HeapGraphSource graphSource` + the `GraphScan?` from config. A nav counter increments per navigation scan; when `graphScan != null && navCount % graphScan.everyNthNavigation == 0`, after the normal scan it runs the graph analysis (acquire → `GraphLeakAnalyzer().analyze(graph, GraphAnalysisOptions(confirmWithReachability: true, appPackages: graphScan.appPackages, minClusterSize: graphScan.minClusterSize))` → map clusters → merge `LeakFinding`s into the emitted report). Skipped while one is in flight; whole path `runSafelyAsync` (never throws). `LeakRadar.graphScanNow()` facade for manual trigger. New findings pass through the existing `reportThreshold` filter.

- [ ] **Step 1: Write failing test** using a `FakeHeapGraphSource` (returns an `InMemoryHeapGraph` with a Timer-rooted app leak) + a fake nav driver: assert the graph scan runs only on the Nth navigation and that a `retainedByNonLiveRoot` finding appears in the emitted report; assert it does NOT run on non-Nth navigations; assert a throwing source degrades to the normal report (never throws).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the counter + gated graph scan + merge + manual facade.
- [ ] **Step 4: Run** full suite `flutter test` → all PASS. analyze clean.
- [ ] **Step 5: Commit** `feat(flutter_leak_radar): every-Nth-nav live graph scan + manual trigger`.

---

### Task 9: UI label for the new kind

**Files:**
- Modify: `packages/flutter_leak_radar/lib/src/ui/leak_radar_screen.dart`, `finding_detail_screen.dart` (wherever `LeakKind` is turned into display text / a chip)
- Test: `packages/flutter_leak_radar/test/ui/leak_radar_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `LeakFinding` with `kind == LeakKind.retainedByNonLiveRoot`.
- Produces: the findings list + detail render a clear label (e.g. "Retained leak" / the `tag` rootKind) and the existing retaining-path tree shows the mapped `RetainingPathView`. Severity tokens reused (no new color system).

- [ ] **Step 1: Write failing widget test** — pump `LeakRadarScreen`/`FindingDetailScreen` with a `retainedByNonLiveRoot` finding (with a retaining path); assert the row renders without overflow and the path tree shows the hops.
- [ ] **Step 2: Run** → FAIL (if a `switch` on kind lacks the case) or adjust.
- [ ] **Step 3: Implement** the label/case.
- [ ] **Step 4: Run** → PASS. analyze clean. `dart format`.
- [ ] **Step 5: Commit** `feat(flutter_leak_radar): render retainedByNonLiveRoot findings`.

---

### Task 10: Example wiring + CHANGELOG

**Files:**
- Modify: `example/lib/main.dart` (enable `GraphScan` in `LeakRadarConfig.standard`), `packages/flutter_leak_radar/CHANGELOG.md`, `example/README.md`
- Test: `cd example && flutter analyze`

**Interfaces:**
- Consumes: `GraphScan` (Task 5).
- Produces: the example enables `graphScan: const GraphScan(everyNthNavigation: 2)` so the live graph detector demos after a couple of navigations; CHANGELOG `## 0.1.0` documents the live retaining-path detector; README notes it.

- [ ] **Step 1:** Add `graphScan: const GraphScan(everyNthNavigation: 2)` to the example's `LeakRadarConfig.standard(...)`.
- [ ] **Step 2: Run** `cd example && flutter analyze` → clean; `cd packages/flutter_leak_radar && flutter test` → all pass.
- [ ] **Step 3:** Add the `## 0.1.0` CHANGELOG entry + README paragraph. `dart format .`.
- [ ] **Step 4: Commit** `docs(flutter_leak_radar): 0.1.0 — live retaining-path detector + example wiring`.

---

## After all tasks

- Add `leak_graph` to the CI gate (`.github/workflows/ci.yaml`: `dart analyze` + `dart test` in `packages/leak_graph`) — a small follow-up so the core is CI-covered.
- Before publishing `flutter_leak_radar` 0.1.0: its `leak_graph` dependency must become a **version** dep (not path/workspace), which means publishing `leak_graph` 0.0.1 first.
- Phase 2 is the final planned phase; on-device validation (does the live graph scan flag the example's leak?) is the proof.
