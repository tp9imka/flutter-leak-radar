// lib/src/engine/graph_scan_runner.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:leak_graph/leak_graph.dart';
import 'package:meta/meta.dart';

import '../util/rate_limited_logger.dart';
import 'heap_snapshot_file.dart';

/// Acquires a heap snapshot and analyses it for retaining-path leaks, returning
/// the [GraphAnalysisResult] — or null when no snapshot source is available or
/// on any error. Implementations must never throw.
///
/// The contract is "acquire + analyse together" (not "return a graph") so the
/// heavy BFS/clustering can run OFF the main isolate: a large heap takes
/// seconds-to-minutes to analyse and would otherwise freeze the UI (ANR).
abstract interface class GraphScanRunner {
  Future<GraphAnalysisResult?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  });
}

/// Heuristic upper bound on heap-snapshot bytes per object. Caps the snapshot
/// file size so a too-large heap is skipped BEFORE it is read + parsed — the
/// secondary OOM guard for the no-VM-service path, where the engine's pre-write
/// object-count gate has no allocation profile to consult.
const int _snapshotBytesPerObject = 96;

/// Production runner: writes a heap snapshot to a file on the **main** isolate
/// (NativeRuntime captures the *current* isolate's heap, so this must run here),
/// then parses + analyses it in a **background** isolate so the UI never blocks.
final class IsolateGraphScanRunner implements GraphScanRunner {
  IsolateGraphScanRunner({RateLimitedLogger? logger}) : _logger = logger;

  final RateLimitedLogger? _logger;

  @override
  Future<GraphAnalysisResult?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  }) async {
    // Capture on the main isolate (a spawned isolate would snapshot its own
    // empty heap). This briefly pauses the isolate but is far short of an ANR.
    final String? path = await writeHeapSnapshotFile();
    if (path == null) {
      _logger?.log(
        'graphScan: heap snapshot unsupported on this platform -> skipped',
        level: LeakLogLevel.verbose,
      );
      return null;
    }
    try {
      // Backstop size gate before the heavy read+parse: skip a snapshot file
      // far too large to analyse in-app. Covers the on-device path where no VM
      // allocation profile exists for the engine's pre-write gate to use.
      final lengthBytes = await File(path).length();
      final maxBytes = maxObjects * _snapshotBytesPerObject;
      if (lengthBytes > maxBytes) {
        _logger?.log(
          'graphScan: snapshot file too large '
          '(${lengthBytes ~/ (1024 * 1024)}MB > ${maxBytes ~/ (1024 * 1024)}MB)'
          ' -> skipped before parse',
          level: LeakLogLevel.verbose,
        );
        return null;
      }
      // Parse + BFS + cluster in a background isolate — the expensive part.
      return await Isolate.run(
        () => _analyzeSnapshotFile(path, options, maxObjects),
      );
    } catch (e) {
      _logger?.log(
        'graphScan: background analysis failed: $e',
        level: LeakLogLevel.verbose,
      );
      return null;
    } finally {
      try {
        await File(path).delete();
      } catch (_) {
        // Best-effort cleanup; never throw.
      }
    }
  }
}

/// Runs in the spawned isolate: reads the snapshot file, parses the graph, and
/// analyses it. Top-level so it is sendable to [Isolate.run]. Returns null when
/// the graph exceeds [maxObjects] (the size guard) — analysing a multi-million
/// node heap is too costly even off the UI thread.
Future<GraphAnalysisResult?> _analyzeSnapshotFile(
  String path,
  GraphAnalysisOptions options,
  int maxObjects,
) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final HeapGraphView graph = heapGraphFromBytes(bytes);
  if (graph.nodeCount >= maxObjects) return null;
  return GraphLeakAnalyzer().analyze(graph, options);
}

/// Test seam: a runner backed by an in-memory result, so engine tests need no
/// real snapshot or isolate.
@visibleForTesting
final class FixedGraphScanRunner implements GraphScanRunner {
  FixedGraphScanRunner(this._result);

  final GraphAnalysisResult? Function(GraphAnalysisOptions options) _result;
  int runCount = 0;

  @override
  Future<GraphAnalysisResult?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  }) async {
    runCount++;
    return _result(options);
  }
}
