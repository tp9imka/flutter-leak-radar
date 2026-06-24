# Retaining-Path Leak Detection — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `leak_graph` — a pure-Dart package that parses a heap snapshot, computes each object's shortest retaining path, flags app-relevant objects retained only through leak-prone roots (timer/stream/closure/finalizer), clusters them by shared path — plus an offline CLI over `.data` dumps.

**Architecture:** A `HeapGraphView` interface decouples analysis from `vm_service`'s `HeapSnapshotGraph`, so the analyzer is tested with hand-built synthetic graphs. A single BFS from the root sentinel yields every object's shortest retaining path; a denylist classifies each path's root kind; leaks are clustered by a normalized path signature and filtered to app packages. A thin `bin/analyze.dart` wraps the same analyzer over a parsed `.data` file.

**Tech Stack:** Dart (no Flutter), `package:vm_service` (`HeapSnapshotGraph`), `package:args` (CLI), `package:meta`, `package:test`.

Spec: `docs/specs/2026-06-24-retaining-path-leak-detection-design.md`.

## Global Constraints

- `leak_graph` is **pure Dart — NO Flutter dependency**. Deps: `vm_service`, `meta`, `args` only (plus `test` dev-dep).
- Hand-rolled immutable value types with manual `==`/`hashCode`/`toJson` — **no freezed, no json_serializable**.
- **Honest degradation:** every cluster carries an explicit `LeakConfidence`; Phase 1 emits only `LeakConfidence.heuristic` (reachability confirmation is Phase 2). Never fabricate a finding or a count.
- Pure functions never throw on a malformed graph — return partial results and append to `GraphAnalysisStats.warnings`.
- Paths are oriented **root → object** (index 0 = first GC-root object, last = the leaked object), matching the existing `RetainingPathView`.
- Minimal comments — only non-obvious "why".
- Phase 1 is offline + denylist only. **No** `live_tree.dart`, **no** `flutter_leak_radar` changes, **no** new `LeakKind` — those are Phase 2.
- This is a new package in the existing melos workspace at `packages/leak_graph/`. Commit on a feature branch, not `main`.

## File Structure

```
packages/leak_graph/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
├── lib/
│   ├── leak_graph.dart                       # public barrel
│   └── src/
│       ├── model/
│       │   ├── root_kind.dart                # RootKind, LeakConfidence
│       │   ├── graph_retaining_path.dart     # GraphHop, GraphRetainingPath
│       │   ├── graph_leak_cluster.dart       # GraphLeakCluster
│       │   └── graph_analysis_result.dart    # GraphAnalysisResult, GraphAnalysisStats
│       ├── graph/
│       │   ├── heap_graph_view.dart          # HeapGraphView, HeapNode, HeapEdge
│       │   ├── vm_snapshot_adapter.dart       # VmSnapshotGraphView
│       │   └── snapshot_loader.dart           # bytes/file → HeapGraphView
│       ├── analysis/
│       │   ├── shortest_retaining_paths.dart  # BFS
│       │   ├── root_classifier.dart           # denylist → RootKind
│       │   ├── app_package_set.dart           # app-relevance set
│       │   ├── clustering.dart                # signature + clustering
│       │   └── graph_leak_analyzer.dart       # orchestration + options
│       └── cli/
│           ├── cli_args.dart                  # arg parsing → CliConfig
│           └── report_renderer.dart           # text + JSON rendering
└── bin/
    └── analyze.dart                           # CLI entrypoint
└── test/
    ├── support/in_memory_heap_graph.dart      # HeapGraphView test double
    ├── model/…_test.dart
    ├── analysis/…_test.dart
    ├── graph/snapshot_round_trip_test.dart
    └── cli/…_test.dart
```

---

### Task 0: Scaffold `leak_graph` package

**Files:**
- Create: `packages/leak_graph/pubspec.yaml`, `packages/leak_graph/analysis_options.yaml`, `packages/leak_graph/lib/leak_graph.dart`, `packages/leak_graph/README.md`
- Modify: root `pubspec.yaml` workspace array / `melos.yaml` (register the new package, matching how `flutter_leak_radar_lint` is registered)

**Interfaces:**
- Produces: a resolvable pure-Dart package named `leak_graph`; empty barrel `lib/leak_graph.dart`.

- [ ] **Step 1: Read the existing lint package's pubspec** to match conventions (Dart SDK floor, lints dep, workspace `resolution:`). Run: `cat packages/flutter_leak_radar_lint/pubspec.yaml`.

- [ ] **Step 2: Write `pubspec.yaml`** — name `leak_graph`, `environment: sdk: ^3.5.0` (match the repo floor), `dependencies: vm_service: ^15.0.0, args: ^2.5.0, meta: ^1.15.0`, `dev_dependencies: test: ^1.25.0, lints: ^5.0.0`. Use `resolution: workspace` only if the other workspace packages do; otherwise omit (mirror the lint package exactly).

- [ ] **Step 3: Write `analysis_options.yaml`** — `include: package:lints/recommended.yaml` plus `language: strict-casts/strict-inference/strict-raw-types: true` (match the runtime package's analysis options: `cat packages/flutter_leak_radar/analysis_options.yaml`).

- [ ] **Step 4: Write the barrel** `lib/leak_graph.dart` with a doc comment and no exports yet (exports added per task). Write a one-paragraph `README.md`.

- [ ] **Step 5: Register in the workspace** the same way `flutter_leak_radar_lint` is registered, then verify resolution. Run: `cd packages/leak_graph && dart pub get` → Expected: resolves with no errors. Run: `dart analyze` → Expected: `No issues found!`.

- [ ] **Step 6: Commit**
```bash
git add packages/leak_graph pubspec.yaml melos.yaml
git commit -m "feat(leak_graph): scaffold pure-Dart heap-graph analysis package"
```

---

### Task 1: Core value models

**Files:**
- Create: `lib/src/model/root_kind.dart`, `lib/src/model/graph_retaining_path.dart`, `lib/src/model/graph_leak_cluster.dart`, `lib/src/model/graph_analysis_result.dart`
- Modify: `lib/leak_graph.dart` (export the four files)
- Test: `test/model/models_test.dart`

**Interfaces:**
- Produces:
  - `enum RootKind { liveTree, timer, stream, staticOrGlobal, closure, finalizer, other }` with `bool get isLeakProne` (true for `timer`, `stream`, `staticOrGlobal`, `closure`, `finalizer`) and `String get label` (e.g. `timer → 'Timer'`).
  - `enum LeakConfidence { heuristic, confirmed }`.
  - `final class GraphHop { final String className; final String? field; final int? index; const GraphHop({required this.className, this.field, this.index}); }` with `==`/`hashCode`/`Map<String,Object?> toJson()`.
  - `final class GraphRetainingPath { final List<GraphHop> hops; final RootKind rootKind; const GraphRetainingPath({required this.hops, required this.rootKind}); }` with `==`/`hashCode` (use `listEquals`-equivalent over `hops`) / `toJson`.
  - `final class GraphLeakCluster { final String className; final Uri? libraryUri; final int instanceCount; final int retainedShallowBytes; final GraphRetainingPath representativePath; final RootKind rootKind; final LeakConfidence confidence; final String signature; const …; }` with `==`/`hashCode`/`toJson`.
  - `final class GraphAnalysisStats { final int totalObjects; final int reachableObjects; final int leakCandidates; final int clusters; final int suppressedByAppFilter; final List<String> warnings; const …; }` + `toJson`.
  - `final class GraphAnalysisResult { final List<GraphLeakCluster> clusters; final GraphAnalysisStats stats; const …; }` + `toJson`.

- [ ] **Step 1: Write failing tests** in `test/model/models_test.dart`:
```dart
import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  test('RootKind.isLeakProne marks holders, not liveTree/other', () {
    expect(RootKind.timer.isLeakProne, isTrue);
    expect(RootKind.stream.isLeakProne, isTrue);
    expect(RootKind.closure.isLeakProne, isTrue);
    expect(RootKind.finalizer.isLeakProne, isTrue);
    expect(RootKind.staticOrGlobal.isLeakProne, isTrue);
    expect(RootKind.liveTree.isLeakProne, isFalse);
    expect(RootKind.other.isLeakProne, isFalse);
  });

  test('GraphHop equality and toJson omit null fields', () {
    const a = GraphHop(className: 'A', field: 'f');
    const b = GraphHop(className: 'A', field: 'f');
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a.toJson(), {'className': 'A', 'field': 'f'});
    expect(const GraphHop(className: 'A').toJson(), {'className': 'A'});
  });

  test('GraphLeakCluster carries count, bytes, confidence, signature', () {
    const path = GraphRetainingPath(
        hops: [GraphHop(className: '_Timer'), GraphHop(className: 'HomeState')],
        rootKind: RootKind.timer);
    const c = GraphLeakCluster(
        className: 'HomeState', libraryUri: null, instanceCount: 3,
        retainedShallowBytes: 480, representativePath: path,
        rootKind: RootKind.timer, confidence: LeakConfidence.heuristic,
        signature: '_Timer>HomeState');
    expect(c.instanceCount, 3);
    expect(c.confidence, LeakConfidence.heuristic);
    expect(c.toJson()['signature'], '_Timer>HomeState');
  });
}
```

- [ ] **Step 2: Run** `cd packages/leak_graph && dart test test/model/models_test.dart` → Expected: FAIL (types undefined).

- [ ] **Step 3: Implement** the four model files per the Interfaces block. `toJson` omits null `field`/`index`/`libraryUri`. `GraphRetainingPath`/result equality compares list contents (write a small private `_listEquals`, or use `package:collection`'s `ListEquality` only if `collection` is already a transitive dep — otherwise hand-roll, no new dep). Add exports to the barrel.

- [ ] **Step 4: Run** the test → Expected: PASS. Run `dart analyze` → Expected: clean.

- [ ] **Step 5: Commit**
```bash
git add packages/leak_graph/lib packages/leak_graph/test/model
git commit -m "feat(leak_graph): core value models (RootKind, path, cluster, result)"
```

---

### Task 2: `HeapGraphView` interface + in-memory test double

**Files:**
- Create: `lib/src/graph/heap_graph_view.dart`, `test/support/in_memory_heap_graph.dart`
- Modify: `lib/leak_graph.dart` (export `heap_graph_view.dart`)
- Test: `test/graph/heap_graph_view_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class HeapGraphView { int get rootId; int get nodeCount; HeapNode node(int id); }`
  - `final class HeapNode { final int id; final String className; final Uri libraryUri; final int shallowSize; final List<HeapEdge> edges; const …; }`
  - `final class HeapEdge { final int targetId; final String? field; final int? index; const …; }`
  - Test double `InMemoryHeapGraph implements HeapGraphView` built from `Map<int, HeapNode>` with `rootId` (default 0). Lets every analysis test build a graph by hand.
- Consumes: nothing.

- [ ] **Step 1: Write failing test** `test/graph/heap_graph_view_test.dart` that builds a 3-node `InMemoryHeapGraph` (root 0 → node 1 → node 2), and asserts `nodeCount == 3`, `node(1).edges.single.targetId == 2`, `node(2).className == 'Leaf'`.

- [ ] **Step 2: Run** → Expected: FAIL.

- [ ] **Step 3: Implement** `HeapGraphView`/`HeapNode`/`HeapEdge` (plain value types, no `vm_service` import) and `InMemoryHeapGraph` in test support. Provide a tiny builder helper in the test double, e.g. `InMemoryHeapGraph.of(Map<int, HeapNode> nodes, {int rootId = 0})`.

- [ ] **Step 4: Run** → Expected: PASS. `dart analyze` clean.

- [ ] **Step 5: Commit**
```bash
git add packages/leak_graph/lib/src/graph/heap_graph_view.dart packages/leak_graph/lib/leak_graph.dart packages/leak_graph/test
git commit -m "feat(leak_graph): HeapGraphView interface + in-memory test double"
```

---

### Task 3: Shortest retaining paths (BFS)

**Files:**
- Create: `lib/src/analysis/shortest_retaining_paths.dart`
- Modify: barrel export
- Test: `test/analysis/shortest_retaining_paths_test.dart`

**Interfaces:**
- Consumes: `HeapGraphView`, `HeapEdge`.
- Produces:
  - `final class PathLink { final int nodeId; final String? field; final int? index; const …; }` (the edge label INTO `nodeId` from its parent).
  - `final class ShortestRetainingPaths { factory ShortestRetainingPaths.compute(HeapGraphView graph); bool isReachable(int nodeId); List<PathLink>? pathTo(int nodeId); }` — `pathTo` returns the links from the first GC-root object (root → object order, sentinel excluded) to `nodeId`, or `null` if unreachable. BFS guarantees shortest.

- [ ] **Step 1: Write failing tests**:
```dart
// Graph: 0(root) -> 1 -> 2 -> 3 ; and a shortcut 0 -> 3 directly.
// Shortest path to 3 must be the direct [3], not [1,2,3].
test('picks the shortest root path when multiple exist', () { … });
test('unreachable node returns null / isReachable false', () { … });
test('path links carry the edge label into each node', () { … });
```
(Build the graphs with `InMemoryHeapGraph`; assert `paths.pathTo(3)!.map((l) => l.nodeId)` equals `[3]`.)

- [ ] **Step 2: Run** → Expected: FAIL.

- [ ] **Step 3: Implement** BFS from `graph.rootId` over `node(id).edges`: `visited` set, `parent` map `int → int`, `parentEdge` map `int → HeapEdge`. Skip the sentinel `rootId` itself in the reconstructed path. `pathTo` walks `parent` from the target back to a direct child of `rootId`, then reverses, attaching each node's `parentEdge` label as a `PathLink`. O(V+E), iterative (no recursion — heaps are large).

- [ ] **Step 4: Run** → Expected: PASS. `dart analyze` clean.

- [ ] **Step 5: Commit**
```bash
git commit -am "feat(leak_graph): shortest retaining paths via BFS from GC roots"
```

---

### Task 4: Root classifier (denylist)

**Files:**
- Create: `lib/src/analysis/root_classifier.dart`
- Modify: barrel export
- Test: `test/analysis/root_classifier_test.dart`

**Interfaces:**
- Produces: `RootKind classifyRoot(List<String> pathClassNames);` — `pathClassNames` ordered root → object. Returns the most-specific leak-prone `RootKind` found among the holders nearest the root, else `RootKind.other`. Phase 1 never returns `liveTree`.
- Consumes: `RootKind`.

Classification rules (precedence top→bottom; first match wins, scanning the path from the root end):
- name `== 'Timer'` or `== '_Timer'` → `timer`
- name ends with `'StreamSubscription'` or `'StreamController'` → `stream`
- name `== 'Finalizer'`, `'NativeFinalizer'`, or ends with `'FinalizerEntry'` → `finalizer`
- name `== '_Closure'`, `'Closure'`, `'Context'`, or `'_Context'` → `closure`
- the first (root-adjacent) node is a `'Library'`, `'Class'`, `'Type'`, `'_Type'`, or `'PatchClass'` → `staticOrGlobal`
- otherwise → `other`

- [ ] **Step 1: Write failing tests** — one per rule, e.g.:
```dart
expect(classifyRoot(['_Timer', 'HomeState']), RootKind.timer);
expect(classifyRoot(['_BufferingStreamSubscription', 'AppCubit']), RootKind.stream);
expect(classifyRoot(['Library', 'AppRegistry', 'Foo']), RootKind.staticOrGlobal);
expect(classifyRoot(['_Closure', 'Captured']), RootKind.closure);
expect(classifyRoot(['SomeWidget', 'SomeState']), RootKind.other);
```

- [ ] **Step 2: Run** → Expected: FAIL.

- [ ] **Step 3: Implement** `classifyRoot` with the precedence rules above (iterate from the root end; match by exact name and suffix). Keep predicates as small named helpers.

- [ ] **Step 4: Run** → Expected: PASS. `dart analyze` clean.

- [ ] **Step 5: Commit**
```bash
git commit -am "feat(leak_graph): denylist root classifier (timer/stream/closure/finalizer/static)"
```

---

### Task 5: App-package set (relevance source)

**Files:**
- Create: `lib/src/analysis/app_package_set.dart`
- Modify: barrel export
- Test: `test/analysis/app_package_set_test.dart`

**Interfaces:**
- Produces:
  - `final class AppPackageSet { bool contains(Uri libraryUri); factory AppPackageSet.from(Iterable<String> packageNames); factory AppPackageSet.autoDetect(Iterable<Uri> allLibraryUris); static const Set<String> sdkDenylist; }`
  - `contains` is true when `libraryUri.scheme == 'package'` and its package segment is in the set.
  - `autoDetect`: collect every `package:<name>` from `allLibraryUris`, drop names matching `sdkDenylist` (`flutter`, `sky_engine`, `leak_graph`, `flutter_leak_radar`, `flutter_leak_radar_lint`, and a small set of common infra packages: `vm_service`, `meta`, `collection`, `async`, `path`, `args`), keep the rest.
- Consumes: nothing.

- [ ] **Step 1: Write failing tests**:
```dart
test('from() matches package: libraries by name', () {
  final s = AppPackageSet.from(['my_app']);
  expect(s.contains(Uri.parse('package:my_app/main.dart')), isTrue);
  expect(s.contains(Uri.parse('package:flutter/widgets.dart')), isFalse);
  expect(s.contains(Uri.parse('dart:core')), isFalse);
});
test('autoDetect drops SDK/framework packages, keeps app packages', () {
  final s = AppPackageSet.autoDetect([
    Uri.parse('package:my_app/main.dart'),
    Uri.parse('package:flutter/widgets.dart'),
    Uri.parse('dart:core'),
  ]);
  expect(s.contains(Uri.parse('package:my_app/x.dart')), isTrue);
  expect(s.contains(Uri.parse('package:flutter/x.dart')), isFalse);
});
```

- [ ] **Step 2: Run** → Expected: FAIL.

- [ ] **Step 3: Implement** parsing the package name from `package:<name>/…` (first path segment) and the denylist filtering.

- [ ] **Step 4: Run** → Expected: PASS. `dart analyze` clean.

- [ ] **Step 5: Commit**
```bash
git commit -am "feat(leak_graph): AppPackageSet with auto-detect of app packages"
```

---

### Task 6: Clustering (signature + grouping)

**Files:**
- Create: `lib/src/analysis/clustering.dart`
- Modify: barrel export
- Test: `test/analysis/clustering_test.dart`

**Interfaces:**
- Produces:
  - `final class LeakRecord { final String className; final Uri libraryUri; final int shallowSize; final GraphRetainingPath path; final List<Uri> pathLibraries; final RootKind rootKind; final String signature; const …; }` (the analyzer builds these; clustering consumes them).
  - `String pathSignature(List<GraphHop> hops, {int maxDepth = 12});` — join the last `maxDepth` hops as `Class[.field]` separated by `'>'`; collapse array `index` to `'[]'`.
  - `List<GraphLeakCluster> clusterLeaks(List<LeakRecord> leaks, {int minClusterSize = 2});` — group by `signature`; per group emit a `GraphLeakCluster` with `instanceCount = group.length`, `retainedShallowBytes = sum(shallowSize)`, `representativePath = first.path`, `className = first.className`, `libraryUri = first.libraryUri`, `rootKind = first.rootKind`, `confidence = LeakConfidence.heuristic`; drop groups smaller than `minClusterSize`; rank by `instanceCount` desc then `retainedShallowBytes` desc.

- [ ] **Step 1: Write failing tests**:
```dart
test('pathSignature normalizes fields and array indices', () {
  expect(pathSignature(const [GraphHop(className:'_Timer'),
      GraphHop(className:'List', index: 4), GraphHop(className:'HomeState', field:'state')]),
      '_Timer>List[]>HomeState.state');
});
test('clusterLeaks groups same-signature leaks and counts them', () {
  // two LeakRecords with identical signature -> one cluster, count 2, bytes summed
});
test('clusterLeaks drops clusters below minClusterSize', () { … });
test('clusters ranked by count then bytes', () { … });
```

- [ ] **Step 2: Run** → Expected: FAIL.

- [ ] **Step 3: Implement** `pathSignature` and `clusterLeaks` (group with a `Map<String, List<LeakRecord>>`, build clusters, sort).

- [ ] **Step 4: Run** → Expected: PASS. `dart analyze` clean.

- [ ] **Step 5: Commit**
```bash
git commit -am "feat(leak_graph): path-signature clustering of leak records"
```

---

### Task 7: `GraphLeakAnalyzer` orchestration

**Files:**
- Create: `lib/src/analysis/graph_leak_analyzer.dart`
- Modify: barrel export
- Test: `test/analysis/graph_leak_analyzer_test.dart`

**Interfaces:**
- Consumes: `HeapGraphView`, `ShortestRetainingPaths`, `classifyRoot`, `AppPackageSet`, `clusterLeaks`, `pathSignature`, all models.
- Produces:
  - `final class GraphAnalysisOptions { final List<String> appPackages; final bool disableAppFilter; final int minClusterSize; final int maxSignatureDepth; const GraphAnalysisOptions({this.appPackages = const [], this.disableAppFilter = false, this.minClusterSize = 2, this.maxSignatureDepth = 12}); }`
  - `final class GraphLeakAnalyzer { const GraphLeakAnalyzer(); GraphAnalysisResult analyze(HeapGraphView graph, [GraphAnalysisOptions options = const GraphAnalysisOptions()]); }`

Algorithm:
1. `paths = ShortestRetainingPaths.compute(graph)`.
2. For each reachable node id `> ` the root: build `pathLinks = paths.pathTo(id)`; derive `pathClassNames` (via `graph.node(link.nodeId).className`) and `pathLibraries` (`graph.node(link.nodeId).libraryUri`). `rootKind = classifyRoot(pathClassNames)`. If `!rootKind.isLeakProne` skip.
3. Build `GraphRetainingPath(hops: pathLinks → GraphHop(className, field, index), rootKind)`, then a `LeakRecord` (className/libraryUri/shallowSize of the terminal node, path, pathLibraries, rootKind, `signature = pathSignature(hops, maxDepth: options.maxSignatureDepth)`).
4. App-relevance (unless `disableAppFilter`): build `appSet = options.appPackages.isEmpty ? AppPackageSet.autoDetect(all node libraryUris) : AppPackageSet.from(options.appPackages)`. Keep a `LeakRecord` iff `appSet.contains(leak.libraryUri)` or any `leak.pathLibraries` is contained. Count drops as `suppressedByAppFilter`.
5. `clusters = clusterLeaks(kept, minClusterSize: options.minClusterSize)`.
6. Return `GraphAnalysisResult(clusters, GraphAnalysisStats(totalObjects, reachableObjects, leakCandidates, clusters.length, suppressedByAppFilter, warnings))`.

- [ ] **Step 1: Write failing tests** using `InMemoryHeapGraph`:
```dart
test('flags an app class retained via a Timer, clustered by count', () {
  // root 0 -> _Timer(1) -> List(2) -> [HomeState(3), HomeState(4)]
  //   HomeState in package:my_app; expect 1 cluster, rootKind timer, count 2.
});
test('does not flag objects whose root is not leak-prone', () {
  // root 0 -> SomeWidget(1) -> SomeState(2): RootKind.other -> no clusters.
});
test('app filter suppresses flutter-only leaks unless disabled', () {
  // _Timer -> framework class in package:flutter -> suppressed by default,
  // kept when options.disableAppFilter = true.
});
test('stats report totals and suppressed counts', () { … });
```

- [ ] **Step 2: Run** → Expected: FAIL.

- [ ] **Step 3: Implement** `GraphAnalysisOptions` + `GraphLeakAnalyzer.analyze` per the algorithm.

- [ ] **Step 4: Run** → Expected: PASS. `dart analyze` clean.

- [ ] **Step 5: Commit**
```bash
git commit -am "feat(leak_graph): GraphLeakAnalyzer end-to-end (paths→classify→cluster→filter)"
```

---

### Task 8: VM snapshot adapter + loader (real `.data`)

**Files:**
- Create: `lib/src/graph/vm_snapshot_adapter.dart`, `lib/src/graph/snapshot_loader.dart`
- Modify: barrel export
- Test: `test/graph/snapshot_round_trip_test.dart`

**Interfaces:**
- Consumes: `HeapGraphView`/`HeapNode`/`HeapEdge`, `package:vm_service` (`HeapSnapshotGraph`, `HeapSnapshotObject`, `HeapSnapshotClass`).
- Produces:
  - `final class VmSnapshotGraphView implements HeapGraphView { VmSnapshotGraphView(this._graph); }` — `rootId = 0`; `nodeCount = _graph.objects.length`; `node(id)` builds a `HeapNode` from `objects[id]`: `className = klass.name`, `libraryUri = klass.libraryUri`, `shallowSize`, and `edges` from `references`. Edge labels: for an instance object map `references[i]` to the field whose `index == i` in `klass.fields` (else `field: null`); when `object.data is HeapSnapshotObjectLengthData` treat refs as elements and set `index: i`.
  - `HeapGraphView heapGraphFromBytes(Uint8List bytes)` → `VmSnapshotGraphView(HeapSnapshotGraph.fromChunks([ByteData.sublistView(bytes)], calculateReferrers: false, decodeIdentityHashCodes: false))`.
  - `Future<HeapGraphView> loadHeapGraph(File file)` → reads bytes → `heapGraphFromBytes`.

- [ ] **Step 1: Write the failing test** `test/graph/snapshot_round_trip_test.dart` that generates a real snapshot of the test isolate in-process, then loads it:
```dart
import 'dart:developer';
import 'dart:io';
import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  test('loads a real heap snapshot and exposes nodes + reachable root', () async {
    final dir = Directory.systemTemp.createTempSync('leak_graph_test');
    final path = '${dir.path}/test_heap.data';
    try {
      NativeRuntime.writeHeapSnapshotToFile(path);
    } catch (_) {
      // NativeRuntime unavailable in this VM — skip (kept honest, not a fake pass).
      markTestSkipped('NativeRuntime.writeHeapSnapshotToFile unsupported here');
      return;
    }
    final graph = await loadHeapGraph(File(path));
    expect(graph.nodeCount, greaterThan(0));
    final paths = ShortestRetainingPaths.compute(graph);
    // At least one well-known core class should be present and reachable.
    final hasString = List.generate(graph.nodeCount, (i) => i).any((i) {
      final n = graph.node(i);
      return (n.className == 'String' || n.className.endsWith('String'));
    });
    expect(hasString, isTrue);
    dir.deleteSync(recursive: true);
  });
}
```

- [ ] **Step 2: Run** `dart test test/graph/snapshot_round_trip_test.dart` → Expected: FAIL (functions undefined). If, once implemented, `writeHeapSnapshotToFile` is unsupported in the test VM, the test self-skips with a reason — note this in the task report rather than forcing a pass.

- [ ] **Step 3: Implement** `VmSnapshotGraphView`, `heapGraphFromBytes`, `loadHeapGraph`. Build `HeapNode.edges` from `object.references`; label via `klass.fields` (match by field `index`) or array index. Guard against the sentinel (`id == 0`) and classes with empty names.

- [ ] **Step 4: Run** → Expected: PASS (or self-skip with reason). `dart analyze` clean.

- [ ] **Step 5: Commit**
```bash
git commit -am "feat(leak_graph): vm_service HeapSnapshotGraph adapter + .data loader"
```

---

### Task 9: Offline CLI

**Files:**
- Create: `lib/src/cli/cli_args.dart`, `lib/src/cli/report_renderer.dart`, `bin/analyze.dart`
- Modify: barrel export (`report_renderer` only; `bin/` is not exported)
- Test: `test/cli/cli_args_test.dart`, `test/cli/report_renderer_test.dart`

**Interfaces:**
- Produces:
  - `final class CliConfig { final String dumpPath; final List<String> appPackages; final bool all; final int minCluster; final int top; final String? jsonOut; const …; }` and `CliConfig parseCliArgs(List<String> argv);` (using `package:args`; throws `FormatException` with a usage message on bad input or missing positional).
  - `String renderReport(GraphAnalysisResult result, {int top});` — header (totals, suppressed), then up to `top` clusters: `× <count>  <ClassName>  (<bytes> B)  [<rootKind.label>]` then the representative path as `root > … > object`.
  - `String renderJson(GraphAnalysisResult result);` — `jsonEncode(result.toJson())`.
  - `bin/analyze.dart` `main(argv)`: `parseCliArgs` → `loadHeapGraph` → `GraphLeakAnalyzer().analyze(graph, options)` → print `renderReport`; if `--json`, write `renderJson` to the file. Exit code 2 on `FormatException`/`FileSystemException`.

- [ ] **Step 1: Write failing tests**:
```dart
// cli_args_test.dart
test('parses dump path, repeated --package, flags, defaults', () {
  final c = parseCliArgs(['dump.data', '--package', 'a', '--package', 'b', '--all', '--min-cluster', '3']);
  expect(c.dumpPath, 'dump.data');
  expect(c.appPackages, ['a', 'b']);
  expect(c.all, isTrue);
  expect(c.minCluster, 3);
  expect(c.top, 50); // default
});
test('throws FormatException when dump path is missing', () {
  expect(() => parseCliArgs(['--all']), throwsFormatException);
});
// report_renderer_test.dart
test('renderReport lists clusters with count, bytes, rootKind and path', () {
  // build a GraphAnalysisResult with one cluster, assert the string contains
  // '× 3', 'HomeState', '[Timer]', and '_Timer > HomeState'.
});
test('renderJson emits parseable JSON with a clusters array', () {
  expect(jsonDecode(renderJson(result))['clusters'], isA<List>());
});
```

- [ ] **Step 2: Run** → Expected: FAIL.

- [ ] **Step 3: Implement** `cli_args.dart` (`ArgParser` with `dump` positional + `package` multi-option + `all`/`min-cluster`/`top`/`json`), `report_renderer.dart`, and `bin/analyze.dart`. `bin/analyze.dart` maps `CliConfig` → `GraphAnalysisOptions(appPackages: config.appPackages, disableAppFilter: config.all, minClusterSize: config.minCluster)`.

- [ ] **Step 4: Run** all package tests: `dart test` → Expected: ALL PASS. `dart analyze` → clean.

- [ ] **Step 5: Commit**
```bash
git commit -am "feat(leak_graph): offline CLI (analyze .data → ranked report + JSON)"
```

---

## After all tasks

- Update `packages/leak_graph/README.md` with the CLI usage block and a one-paragraph description of the denylist heuristic + the `--all` flag.
- Run the full suite once more: `cd packages/leak_graph && dart test && dart analyze`.
- Phase 2 (live-tree reachability + `flutter_leak_radar` integration + new `LeakKind` + UI + example wiring) is a separate plan that builds on these interfaces.
