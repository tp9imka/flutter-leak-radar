// Analyses a VM heap snapshot and prints the suspected leak clusters with their
// retaining paths — no live VM-service connection required.
//
// Run:
//   dart run example/leak_graph_example.dart path/to/heap.data
//
// The `.data` file is a VM heap snapshot, e.g. one written on-device by
// `NativeRuntime.writeHeapSnapshotToFile` (dart:developer) or exported from
// Flutter DevTools (Memory › Save).
import 'dart:io';

import 'package:leak_graph/leak_graph.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run example/leak_graph_example.dart <heap.data>',
    );
    exitCode = 64;
    return;
  }

  // Parse the snapshot into an object graph.
  final HeapGraphView graph = await loadHeapGraph(File(args.first));

  // Detect leaks: objects retained only by leak-prone roots (timers, streams,
  // closures, statics), each attributed to the deepest app-owned object on its
  // retaining path and clustered by path signature.
  final result = GraphLeakAnalyzer().analyze(
    graph,
    const GraphAnalysisOptions(
      minClusterSize: 1,
      confirmWithReachability: true,
    ),
  );

  stdout.writeln(
    'Scanned ${result.stats.totalObjects} objects '
    '(${result.stats.reachableObjects} reachable); '
    '${result.clusters.length} leak cluster(s):\n',
  );
  for (final cluster in result.clusters) {
    stdout.writeln(
      '• ${cluster.className} x${cluster.instanceCount}  '
      '(root: ${cluster.rootKind.label})',
    );
    for (final hop in cluster.representativePath.hops) {
      final field = hop.field != null ? '.${hop.field}' : '';
      stdout.writeln('    <- ${hop.className}$field');
    }
  }

  // The same snapshot also yields a per-class histogram, the standalone
  // (VM-service-free) source for heap-growth detection.
  stdout.writeln('\n${graph.classHistogram().length} classes in the snapshot.');
}
