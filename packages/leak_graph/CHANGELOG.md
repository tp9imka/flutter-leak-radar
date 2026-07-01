## Unreleased

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

## 0.2.0

- `computeDiff` — diffs two class histograms into per-class instance/byte deltas
  (growth and shrinkage), backing snapshot-to-snapshot comparison.
- Standalone heap-growth and retaining-path analysis directly from an on-device
  heap snapshot — no live VM-service connection required.

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
