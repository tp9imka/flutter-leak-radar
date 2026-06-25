// lib/src/engine/graph_scan_runner.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:leak_graph/leak_graph.dart';
import 'package:meta/meta.dart';

import '../precise/force_gc.dart';
import '../util/rate_limited_logger.dart';
import 'heap_snapshot_file.dart';

/// Acquires a heap snapshot and analyses it for retaining-path leaks, returning
/// the [GraphAnalysisResult] — or null when no snapshot source is available or
/// on any error. Implementations must never throw.
///
/// The contract is "acquire + analyse together" (not "return a graph") so the
/// heavy BFS/clustering can run OFF the main isolate: a large heap takes
/// seconds-to-minutes to analyse and would otherwise freeze the UI (ANR).
/// The product of one graph scan: the retaining-path [result] plus a class
/// histogram derived from the SAME heap snapshot, so heap-growth can be
/// measured on-device without a VM-service `getAllocationProfile` call.
final class GraphScanOutcome {
  final GraphAnalysisResult result;
  final List<ClassCount> histogram;

  const GraphScanOutcome({required this.result, required this.histogram});
}

abstract interface class GraphScanRunner {
  Future<GraphScanOutcome?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  });

  /// Captures a heap snapshot and returns the retaining path to the first
  /// reachable instance of [className], or null. Standalone (no VM service);
  /// the parse + BFS run off the main isolate. Never throws.
  Future<GraphRetainingPath?> retainingPathForClass(
    String className, {
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
  IsolateGraphScanRunner({
    RateLimitedLogger? logger,
    Future<void> Function()? gcForcer,
  }) : _logger = logger,
       _gcForcer =
           gcForcer ?? (() => forceGc(timeout: const Duration(seconds: 4)));

  final RateLimitedLogger? _logger;
  final Future<void> Function() _gcForcer;

  /// Forces a GC right before a snapshot so it counts LIVE objects, not the
  /// transient garbage awaiting collection that otherwise inflates per-class
  /// counts (a leaked-vs-garbage `_Timer` mismatch). Best-effort — never throws.
  Future<void> _forceGcSafely() async {
    try {
      await _gcForcer();
    } catch (_) {
      // A GC failure must never break the scan.
    }
  }

  @override
  Future<GraphScanOutcome?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  }) async {
    // GC first so the snapshot (and its class histogram) counts live objects,
    // not transient garbage. Capture on the main isolate (a spawned isolate
    // would snapshot its own empty heap) — briefly pauses, far short of an ANR.
    await _forceGcSafely();
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

  @override
  Future<GraphRetainingPath?> retainingPathForClass(
    String className, {
    required int maxObjects,
  }) async {
    await _forceGcSafely();
    final String? path = await writeHeapSnapshotFile();
    if (path == null) return null;
    try {
      final lengthBytes = await File(path).length();
      if (lengthBytes > maxObjects * _snapshotBytesPerObject) return null;
      return await Isolate.run(
        () => _pathForClassInFile(path, className, maxObjects),
      );
    } catch (e) {
      _logger?.log(
        'retainingPathForClass: background lookup failed: $e',
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
/// BFS-finds the retaining path to an instance of [className]. Top-level so it
/// is sendable to [Isolate.run].
Future<GraphRetainingPath?> _pathForClassInFile(
  String path,
  String className,
  int maxObjects,
) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final HeapGraphView graph = heapGraphFromBytes(bytes);
  if (graph.nodeCount >= maxObjects) return null;
  return retainingPathForClass(graph, className);
}

/// Runs in the spawned isolate: reads the snapshot file, parses the graph,
/// analyses it, and derives the class histogram from the same graph. Top-level
/// so it is sendable to [Isolate.run]. Returns null when the graph exceeds
/// [maxObjects] (the size guard) — analysing a multi-million node heap is too
/// costly even off the UI thread.
Future<GraphScanOutcome?> _analyzeSnapshotFile(
  String path,
  GraphAnalysisOptions options,
  int maxObjects,
) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final HeapGraphView graph = heapGraphFromBytes(bytes);
  if (graph.nodeCount >= maxObjects) return null;
  final result = GraphLeakAnalyzer().analyze(graph, options);
  // Same snapshot, second cheap pass: the class histogram that lets heap-growth
  // detection work standalone (no VM-service allocation profile required).
  final histogram = graph.classHistogram();
  return GraphScanOutcome(result: result, histogram: histogram);
}

/// Test seam: a runner backed by an in-memory result, so engine tests need no
/// real snapshot or isolate.
@visibleForTesting
final class FixedGraphScanRunner implements GraphScanRunner {
  FixedGraphScanRunner(
    this._result, {
    List<ClassCount> histogram = const [],
    GraphRetainingPath? Function(String className)? pathForClass,
  }) : _histogram = histogram,
       _pathForClass = pathForClass;

  final GraphAnalysisResult? Function(GraphAnalysisOptions options) _result;
  final List<ClassCount> _histogram;
  final GraphRetainingPath? Function(String className)? _pathForClass;
  int runCount = 0;

  @override
  Future<GraphScanOutcome?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  }) async {
    runCount++;
    final r = _result(options);
    if (r == null) return null;
    return GraphScanOutcome(result: r, histogram: _histogram);
  }

  @override
  Future<GraphRetainingPath?> retainingPathForClass(
    String className, {
    required int maxObjects,
  }) async => _pathForClass?.call(className);
}
