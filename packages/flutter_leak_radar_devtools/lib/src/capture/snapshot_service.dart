import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:vm_service/vm_service.dart';

import 'snapshot_bundle.dart';

/// Captures a heap snapshot via the host-side VM service and runs
/// [GraphLeakAnalyzer] analysis in a background isolate.
///
/// Uses [compute] so the heavy BFS + clustering never blocks the UI thread.
/// The [VmService] connection is owned by [serviceManager]; this service
/// only borrows the reference — it does not close it.
class SnapshotService {
  const SnapshotService();

  static const _log = 'leakRadarDevTools.snapshot';

  /// Captures a heap snapshot from [vmService] for [isolateRef] and runs
  /// [GraphLeakAnalyzer.analyze] in a background isolate.
  ///
  /// [label] is a human-readable name for the bundle (e.g. "Baseline").
  /// Never throws — returns a bundle with an empty analysis result on error
  /// and logs the exception via [developer.log].
  Future<SnapshotBundle> capture({
    required VmService vmService,
    required IsolateRef isolateRef,
    String label = '',
  }) async {
    developer.log('Capturing heap snapshot (label=$label)', name: _log);
    final capturedAt = DateTime.now();

    try {
      final graph = await HeapSnapshotGraph.getSnapshot(vmService, isolateRef);
      developer.log('Snapshot: ${graph.objects.length} objects', name: _log);
      final view = VmSnapshotGraphView(graph);
      final histogram = view.classHistogram();

      // Run expensive BFS analysis off the UI thread.
      // VmSnapshotGraphView is a pure-Dart object built from parsed data,
      // so it should be isolate-safe to pass via compute().
      //
      // KNOWN CONCERN: if HeapSnapshotGraph internally holds any
      // non-SendPort-safe state (e.g. Finalizers, native peers), compute()
      // will throw at runtime with an "Illegal argument" error. In that case,
      // consider serialising to Uint8List via HeapSnapshotGraph.toChunks()
      // and reconstructing inside the isolate with heapGraphFromBytes().
      final result = await compute(_analyzeInIsolate, view);

      return SnapshotBundle(
        capturedAt: capturedAt,
        label: label,
        histogram: histogram,
        analysisResult: result,
      );
    } catch (e, s) {
      developer.log(
        'Snapshot capture failed',
        name: _log,
        error: e,
        stackTrace: s,
      );
      return SnapshotBundle(
        capturedAt: capturedAt,
        label: label,
        histogram: const [],
        analysisResult: const GraphAnalysisResult(
          clusters: [],
          stats: GraphAnalysisStats(
            totalObjects: 0,
            reachableObjects: 0,
            leakCandidates: 0,
            clusters: 0,
            suppressedByAppFilter: 0,
            warnings: ['Snapshot capture failed — see console for details.'],
          ),
        ),
      );
    }
  }
}

/// Top-level function required by [compute]: must be a top-level or static fn.
///
/// Runs [GraphLeakAnalyzer.analyze] with default options. The function
/// receives a [VmSnapshotGraphView] — a pure-Dart object — which is expected
/// to be isolate-safe (no native peers or Finalizers).
GraphAnalysisResult _analyzeInIsolate(VmSnapshotGraphView view) {
  return const GraphLeakAnalyzer().analyze(view, const GraphAnalysisOptions());
}
