## 0.2.2

- `GraphAnalysisResult.classPathDistributions` — per-class distribution of a
  class's instances across their distinct shortest retaining paths (grouped by
  path signature), materialised for a bounded set of classes. Backs a
  native-DevTools-style "N instances → X via path A, Y via path B…" breakdown.
  Each `PathBucket` carries a representative path, instance count, and summed
  shallow bytes; `ClassPathDistribution` reports `sampledInstances` vs
  `totalInstances` so a capped (sampled) breakdown is never presented as
  complete. New `buildClassPathDistributions` analyzer pass and `PathBucket` /
  `ClassPathDistribution` models (JSON round-trip supported).

## 0.2.1

- Docs + packaging only (no library code change from 0.2.0): rewritten README
  (standalone-first framing; documents `classRootProfiles`, JSON round-trip,
  and the CLI) and expose the `leak_capture` command via `executables:`. 0.2.0
  shipped the same code but with a stale README and without the executable
  entry.

## 0.2.0

- `GraphAnalysisResult.classRootProfiles` — a `ClassRootProfile` for EVERY
  class reachable from the GC root (not just leak-prone-rooted clusters),
  grouping each class's instances by the `RootKind` of their closest
  retaining root. Lets a UI separate live-UI-tree classes from leak-prone
  ones instead of only ever seeing leak candidates. A bounded subset of
  classes (the largest by instance count, plus any class with a leak-prone
  instance) also gets a representative shortest retaining path.
- `toJson` / `fromJson` on `ClassCount`, `GraphHop`, `GraphRetainingPath`,
  `GraphLeakCluster`, `GraphAnalysisStats`, `GraphAnalysisResult`, and the new
  `ClassRootProfile` — a full analysis run can now round-trip through JSON
  for snapshot export.
- `computeDiff` — diffs two class histograms into per-class instance/byte deltas
  (growth and shrinkage), backing snapshot-to-snapshot comparison.
- Standalone heap-growth and retaining-path analysis directly from an on-device
  heap snapshot — no live VM-service connection required.
- Command-line heap dumper for capturing snapshots off a running app:
  - `bin/capture.dart` (run via `dart run leak_graph:capture`) — connects to a
    VM Service URI, streams a raw `dartheap` snapshot to a file, and can
    optionally run the analysis in the same pass.
  - `tool/heapdump.sh` — a standalone bash + adb + python3 dumper (no Dart
    toolchain) that discovers the VM Service URL from logcat, forwards the
    port, and streams the same `dartheap` file straight off an Android device.

## 0.1.0

Initial release.

Pure-Dart heap-snapshot analysis: load a VM heap snapshot, build an object
graph, and find the retaining paths that keep suspected leaks alive — with no
dependency on a live VM-service connection.

- `heapGraphFromBytes` / `loadHeapGraph` — parse a `.data` heap snapshot
  (e.g. from `NativeRuntime.writeHeapSnapshotToFile`) into a `HeapGraphView`.
  Never throws on malformed input; returns a sentinel graph instead.
- `GraphLeakAnalyzer.analyze` — the end-to-end pipeline: BFS shortest retaining
  paths, leak-prone root classification (timer / stream / closure / finalizer /
  static), app-relevance filtering, optional live-tree confirmation, and
  clustering by retaining-path signature. Each leak is attributed to the
  **deepest app-owned object** on its path, with the SDK chain kept as detail.
- `retainingPathForClass(graph, className)` — shortest retaining path to the
  first reachable instance of a class (standalone, no VM service).
- `HeapGraphView.classHistogram()` — per-class instance counts derived from the
  snapshot, for VM-service-free heap-growth detection.
- `bin/analyze.dart` — CLI that analyses a heap-snapshot file and renders a
  report.
