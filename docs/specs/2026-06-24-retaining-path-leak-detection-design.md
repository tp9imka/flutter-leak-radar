# Retaining-Path Leak Detection — Design

**Status:** approved design (2026-06-24), pre-implementation.

## Goal

A graph-based, near-zero-config leak detector: parse the heap object graph,
compute each object's shortest retaining path, and flag **app-relevant** objects
that are retained **only through non-live roots** (timers, streams, statics,
closures) — clustered by shared retaining path. Delivered as three units:

1. a pure-Dart analysis **core** (`leak_graph`),
2. an offline **CLI** over `.data` heap dumps,
3. **live on-device** integration that runs every Nth navigation and surfaces
   results in the existing inspector.

It complements the two existing detectors. Heap growth/maxLive is count-based
(needs ≥2 samples or a climbing count); precise `track()`/`markDisposed()` needs
instrumentation. Neither catches a **single, stable** retained instance with no
instrumentation. Retaining-path analysis does, and it explains *why* an object
is retained.

## Feasibility (verified against `package:vm_service` 15.0.0)

- `HeapSnapshotGraph` (in `vm_service/src/snapshot_graph.dart`) is constructible
  two ways: **live** `HeapSnapshotGraph.getSnapshot(service, isolate, …)` over a
  VM-service connection, and **offline** `HeapSnapshotGraph.fromChunks([bytes])`
  for a `.data` file (magic header `dartheap`).
- `HeapSnapshotObject` exposes `references` (`Uint32List` of successor object
  indices), `klass`, `shallowSize`, `data` (array length / string value), and
  `identityHashCode`. The GC-root sentinel is `objects[0]`; its `references` are
  the GC roots.
- `HeapSnapshotClass` exposes `name` (simple), `libraryUri` (`Uri`), and `fields`
  (`HeapSnapshotField` with name + index).
- A single forward **BFS from `objects[0]` over `references`** yields, for every
  reachable object, a shortest path from a GC root — i.e. its shortest retaining
  path — in one O(V+E) pass. `referrers`/`calculateReferrers` are NOT needed.

## Classification model (the core decision)

A retained object is a **leak** when, after layering two signals:

1. **Denylist pre-pass (cheap, Phase 1):** the object's shortest retaining path
   is anchored in a known leak-prone holder — its `RootKind` is one of
   `timer`, `stream`, `staticOrGlobal`, `closure`, `finalizer`. These are leak
   *candidates*.
2. **Live-tree reachability (confirm/suppress, Phase 2):** the object is **not**
   reachable from the live UI-tree anchor. An object reachable from the live tree
   is in use → suppressed even if a denylisted path also reaches it. An object
   reachable from GC roots but **not** from the live tree, anchored in a
   denylisted root, is a **confirmed** leak.

`RootKind` doubles as the human explanation ("retained by Timer"). Confidence:
`heuristic` (denylist only, Phase 1 / no live anchor found) vs `confirmed`
(reachability-checked, Phase 2).

## Scope / noise filter

Surface only **app-relevant** clusters: the leaked class's `libraryUri` is an
app package, **or** an app package appears on the representative retaining path
(so an app-caused framework leak — e.g. a leaked `ImageStreamCompleter` held by
an app widget — is still surfaced). App packages are configurable; default
auto-detect = `package:` libraries excluding a built-in denylist (`dart:*`,
`package:flutter*`, the `flutter_leak_radar*`/`leak_graph` packages, and the
common Flutter ecosystem). The CLI also offers `--all` to disable this filter
for deep triage.

## Architecture — three units

```
flutter_leak_radar (Flutter)  ──►  leak_graph (pure Dart)  ◄──  leak_graph CLI (pure Dart)
        live acquisition + every-Nth-nav     the brain               offline entrypoint
        + finding mapping + UI reuse
```

Flutter never enters the core or the CLI. The core depends only on
`package:vm_service` and `package:meta`.

### Unit 1 — `leak_graph` core (new pure-Dart package)

**Testability seam.** The analyzer consumes a `HeapGraphView` interface, not
`HeapSnapshotGraph` directly, so unit tests build synthetic graphs by hand with
no real snapshot or device:

```dart
abstract interface class HeapGraphView {
  int get rootId;                  // GC-root sentinel id (0 for VM snapshots)
  int get nodeCount;
  HeapNode node(int id);
}

final class HeapNode {            // pure value type
  final int id;
  final String className;         // simple name
  final Uri libraryUri;
  final int shallowSize;
  final List<HeapEdge> edges;     // out-edges
}

final class HeapEdge {
  final int targetId;
  final String? field;            // field name for instance refs, else null
  final int? index;               // element index for array refs, else null
}
```

`VmSnapshotGraphView implements HeapGraphView` adapts `HeapSnapshotGraph`:
`rootId = 0`; `node(id)` reads `klass.name`/`klass.libraryUri`/`shallowSize`;
edges from `references`, labelling each edge by matching its position to
`klass.fields[i].name` for instance objects and by element index for arrays
(via `object.data` length type).

**Pipeline** (`GraphLeakAnalyzer.analyze(HeapGraphView, GraphAnalysisOptions)`):

1. **Shortest paths** (`retaining_paths.dart`): BFS from `rootId` over `edges`;
   record `depth`, `parent`, and `parentEdge` per reachable node. Reconstruct a
   node's path by walking parents. Unreachable nodes are already collectable →
   ignored.
2. **Root classification** (`root_classifier.dart`): for each node, classify its
   path's anchor into a `RootKind` (`liveTree`, `timer`, `stream`,
   `staticOrGlobal`, `closure`, `finalizer`, `other`) by inspecting the class
   names along the path nearest the root (e.g. a `_Timer`/`Timer` hop → `timer`;
   `*StreamSubscription`/`*StreamController` → `stream`; a class-table/static
   root edge → `staticOrGlobal`; `Closure`/`Context` → `closure`).
3. **Live-tree reachability** (`live_tree.dart`, Phase 2): locate the live anchor
   node(s) by class name (`WidgetsBinding`/`WidgetsFlutterBinding`/`RenderView`/
   root `Element`); BFS from there to build the live-reachable set. Live: may
   resolve the root element's object id via the service for precision, else fall
   back to name match. If no anchor is found, degrade to denylist-only with
   `confidence: heuristic`.
4. **Leak decision:** Phase 1 → candidate ⇔ `RootKind` ∈ denylist. Phase 2 →
   leak ⇔ candidate **and not** live-reachable.
5. **Signature + clustering** (`clustering.dart`): signature = normalized path
   (`Class[.field]` per hop; array indices collapsed to `[]`; depth-capped at a
   configurable `maxSignatureDepth`, default 12 hops nearest the leaked object).
   Cluster leaked nodes by signature. A cluster carries the leaked class name,
   instance count, summed shallow bytes, a representative path, `RootKind`, and
   confidence. **Shared signature across many objects is the headline signal** —
   larger clusters raise severity.
6. **App-relevance filter** (`app_relevance.dart`): drop clusters with no app
   package on the leaked class or representative path (unless options disable it).
7. **Output:** `GraphAnalysisResult { List<GraphLeakCluster> clusters;
   GraphAnalysisStats stats }`, clusters ranked by instance count then bytes.

**Pure-Dart output models** (`model/`): `GraphLeakCluster`, `GraphRetainingPath`,
`GraphHop`, `RootKind`, `LeakConfidence`, `GraphAnalysisResult`,
`GraphAnalysisStats`. Hand-rolled immutable with manual `==`/`hashCode` (no
freezed). The runtime maps these to the existing `LeakFinding`/`RetainingPathView`.

**Core files:** `lib/leak_graph.dart` (barrel); `lib/src/graph/{heap_graph_view,
vm_snapshot_adapter,snapshot_loader}.dart`; `lib/src/analysis/{retaining_paths,
root_classifier,live_tree,clustering,app_relevance,graph_leak_analyzer}.dart`;
`lib/src/model/*.dart`.

### Unit 2 — offline CLI (`bin/analyze.dart` in `leak_graph`)

```
dart run leak_graph:analyze <dump.data> \
  [--package <name>]...   # app packages (repeatable); default auto-detect
  [--all]                 # disable app-relevance filter
  [--min-cluster <N>]     # minimum cluster size to report (default 2)
  [--top <K>]             # show top K clusters (default 50)
  [--json <file>]         # also write machine-readable JSON
```

`snapshot_loader.dart` reads the file bytes → `HeapSnapshotGraph.fromChunks` →
`VmSnapshotGraphView` → `GraphLeakAnalyzer`. Accepts both LeakRadar-captured and
DevTools-exported `.data` dumps (same format). Output: a header (heap size,
object count, analysis time), a ranked table (class ×count, bytes, root kind,
confidence, representative path), and a footer (suppressed/app-filtered counts).
Non-zero exit on usage/parse errors.

### Unit 3 — `flutter_leak_radar` integration (Flutter)

**Config.** A new nullable `GraphScan` on `LeakRadarConfig` (null = disabled;
opt-in because graph analysis is heavier than allocation-profile scans):

```dart
final class GraphScan {
  final int everyNthNavigation;   // default 5
  final int maxGraphObjects;      // size guard; skip if larger (default 500000)
  final List<String> appPackages; // default const [] → auto-detect
  final int minClusterSize;       // default 2
}
```

`LeakRadarConfig.standard()` gains an optional `graphScan` parameter.

**Acquisition** (`HeapGraphSource`): live = `HeapSnapshotGraph.getSnapshot(
service, isolate, calculateReferrers: false, decodeObjectData: true,
decodeIdentityHashCodes: false)` via the existing `VmHeapProbe` connection;
fallback = `writeHeapSnapshotFile()` → read → `fromChunks` when the VM service is
unavailable. Wrapped in `VmSnapshotGraphView`. Size-guarded and never-throw.

**Trigger:** a counter on the existing navigation-scan path; when
`navCount % everyNthNavigation == 0`, after the normal scan, run graph analysis.
Also a manual "deep scan" action (overlay long-press / inspector button).
Debounced, skipped while one is in flight, skipped when the heap exceeds
`maxGraphObjects`.

**Mapping:** each `GraphLeakCluster` → `LeakFinding(className, kind:
LeakKind.retainedByNonLiveRoot, severity: bySize+confidence, liveCount:
instanceCount, growth: 0, library: cluster.libraryUri, tag: rootKind.label,
retainingPath: map(representativePath))`. New `LeakKind.retainedByNonLiveRoot`.
Findings merge into the `LeakReport` and pass through the existing
`reportThreshold` filter.

**UI:** reuse the findings list, severity chips, and the finding-detail
retaining-path tree (which already renders `RetainingPathView`). The new kind
gets a label and reuses severity tokens — minimal new UI.

## Data flow

- **Live:** nav pop → scan → (every Nth) acquire graph → `GraphLeakAnalyzer` →
  clusters → map → merge into report → emit → inspector.
- **Offline:** capture `.data` (LeakRadar export or DevTools) → CLI →
  `GraphLeakAnalyzer` → terminal report / JSON.

## Error handling

- **Core:** pure functions; validate inputs; never throw on a malformed graph —
  return partial results with `stats.warnings`.
- **Runtime:** `runSafelyAsync` throughout; analysis failure degrades to the
  normal scan; size-guarded; never affects the host; full release no-op.
- **CLI:** clear messages; non-zero exit on bad file/format/usage.

## Testing

- **Core (bulk; pure Dart, no device):** synthetic `HeapGraphView` fixtures →
  BFS shortest-path correctness; `RootKind` classification per holder type;
  reachability suppression (live-reachable object is suppressed); signature
  normalization; clustering (same path → one cluster with correct count);
  app-relevance filter. Plus one real `.data` fixture (captured from the example)
  parsed end-to-end.
- **CLI:** golden test on a fixture dump → expected JSON.
- **Runtime:** every-Nth-nav gate counter; acquisition A→B fallback (fake
  source); cluster→finding mapper; config plumbing; widget test that a
  `retainedByNonLiveRoot` finding renders with its path. Fake `HeapGraphView` so
  no device is needed.
- Coverage target ≥ 80%.

## Phasing

- **Phase 1 — offline + denylist:** `leak_graph` core (graph view, VM adapter,
  snapshot loader, BFS, root classifier, clustering, app-relevance, models) +
  CLI + tests. Ships a working offline analyser on the denylist signal.
- **Phase 2 — reachability + live:** live-tree reachability in the core
  (confirm/suppress) + runtime integration (config, acquisition, every-Nth-nav
  gate, mapping, new `LeakKind`, UI) + example wiring + tests.

Each phase is independently shippable and testable.

## Out of scope (YAGNI)

- Cross-snapshot diffing and dominator-tree retained-size (DevTools-grade). We
  use shallow size + counts.
- A GUI for the offline tool (CLI only).
- Per-member retaining-path rendering (representative path per cluster only).

## Global constraints

- `leak_graph` core and CLI are pure Dart with **no Flutter dependency** (only
  `vm_service` + `meta`).
- Runtime graph analysis is opt-in, debug/profile only, full release no-op,
  never-throw, and size-guarded.
- Reuse the existing `LeakFinding`/`RetainingPathView`; no freezed (hand-rolled
  immutable + manual `==`/`hashCode`); honest degradation (explicit `confidence`,
  never fabricate a finding); minimal comments.
