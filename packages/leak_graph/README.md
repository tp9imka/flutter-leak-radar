# leak_graph

[![pub.dev](https://img.shields.io/pub/v/leak_graph.svg)](https://pub.dev/packages/leak_graph)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Pure-Dart heap-snapshot analysis. Loads a Dart VM `dartheap` snapshot, builds an
in-memory object graph, and computes the retaining paths that keep suspected
leaks alive. Works **standalone** from a snapshot file on disk — no live
VM-service connection required — or against a snapshot dumped from a running app.
No Flutter dependency, so it is usable in CLI tools, servers, and Flutter apps
alike.

---

## Installation

```yaml
dependencies:
  leak_graph: ^0.2.0
```

---

## Features

- **Class histogram** — `HeapGraphView.classHistogram()` returns per-class
  instance counts and shallow bytes (`ClassCount`) straight from the snapshot,
  for VM-service-free heap-growth detection.
- **Retaining-path analysis** — `GraphLeakAnalyzer.analyze` runs the end-to-end
  pipeline (BFS shortest retaining paths, leak-prone root classification,
  app-relevance filtering, optional live-tree confirmation, and clustering) and
  returns a `GraphAnalysisResult`. `retainingPathForClass` gives the shortest
  path to a single class on demand.
- **Per-path instance distribution** — `GraphAnalysisResult.classPathDistributions`
  breaks a class's instances down across their distinct shortest retaining paths
  (a "N instances → X via path A, Y via path B…" view) for a bounded set of
  classes, reporting sampled-vs-total so a capped breakdown is never presented
  as complete.
- **Snapshot-to-snapshot diff** — `computeDiff` turns two class histograms into
  per-class instance/byte deltas (`ClassCountDiff`), sorted largest-grower
  first, backing before/after comparison.
- **`classRootProfiles`** — a `ClassRootProfile` for EVERY reachable class (not
  just leak-prone-rooted clusters), grouping each class's instances by the
  `RootKind` of their closest GC root. `looksLive` separates classes retained by
  the live Flutter UI tree from leak-prone ones, so a UI can render a full
  "who retains what" breakdown instead of only leak candidates.
- **JSON round-trip** — `toJson` / `fromJson` on the whole result tree
  (`GraphAnalysisResult`, `GraphLeakCluster`, `GraphRetainingPath`, `GraphHop`,
  `GraphAnalysisStats`, `ClassRootProfile`, `ClassCount`) for snapshot export
  and offline re-analysis.
- **Command-line dumper** — capture a snapshot off a running app without
  DevTools (see below).

---

## Usage

### Analyze a snapshot file

```dart
import 'dart:io';
import 'package:leak_graph/leak_graph.dart';

Future<void> main() async {
  // Load a raw `dartheap` snapshot (e.g. from the CLI below or
  // NativeRuntime.writeHeapSnapshotToFile) — never throws on malformed input.
  final graph = await loadHeapGraph(File('heap.data'));

  final result = GraphLeakAnalyzer().analyze(
    graph,
    const GraphAnalysisOptions(appPackages: ['package:my_app/']),
  );

  for (final cluster in result.clusters) {
    print('${cluster.instanceCount}× ${cluster.className}');
  }

  // Per-class root breakdown, including live-UI-tree classes.
  for (final profile in result.classRootProfiles) {
    final tag = profile.looksLive ? 'live' : 'suspect';
    print('[$tag] ${profile.className}: ${profile.byRoot}');
  }
}
```

`heapGraphFromBytes(Uint8List)` is the synchronous, in-memory equivalent of
`loadHeapGraph`.

### Diff two snapshots for growth

```dart
final before = (await loadHeapGraph(File('a.data'))).classHistogram();
final after = (await loadHeapGraph(File('b.data'))).classHistogram();

for (final d in computeDiff(before, after).take(10)) {
  print('${d.instanceDelta >= 0 ? '+' : ''}${d.instanceDelta} '
        '${d.after.className}');
}
```

### Capture a snapshot from a running app

Dump a live heap over the VM Service — the command-line equivalent of a DevTools
snapshot, no GUI:

```sh
dart run leak_graph:capture --uri http://127.0.0.1:8181/TOKEN=/ -o heap.data
```

Pass `--analyze` to print a leak report in the same pass. When installed
globally (`dart pub global activate leak_graph`) the same tool is available as
`leak_capture`.

For a device with no Dart toolchain, `tool/heapdump.sh` does the same using only
`bash` + `adb` + `python3`, discovering the VM Service URL from logcat:

```sh
tool/heapdump.sh -p com.example.myapp -o heap.data
```

---

## Related packages

Part of the [flutter-leak-radar](https://github.com/tp9imka/flutter-leak-radar)
suite.

| Package | Purpose |
|---|---|
| [`flutter_leak_radar`](https://pub.dev/packages/flutter_leak_radar) | On-device memory leak detector — heap growth, precise retention, overlay. Uses `leak_graph` for retaining-path analysis. |
| [`radar`](https://pub.dev/packages/radar) | Umbrella: one import for both `flutter_leak_radar` + `flutter_perf_radar`. |
| [`radar_trace`](https://pub.dev/packages/radar_trace) | Pure-Dart tracer framework — spans, latency histograms, outlier ring. |

---

## License

MIT — see [LICENSE](LICENSE).
