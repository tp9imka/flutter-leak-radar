import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:leak_graph/leak_graph.dart';

import 'snapshot_bundle.dart';

/// Parses and analyzes heap snapshots off the UI thread, host-agnostically.
///
/// `fromGraph` analyzes an already-parsed graph (the live-capture path);
/// `fromBytes` parses raw `dartheap` bytes and analyzes them entirely inside
/// the background isolate (the file-import path — the graph never touches the
/// main isolate, which matters for large desktop dumps).
///
/// Uses [compute], which runs on a real isolate on native and a web worker /
/// main thread on web, so a single implementation serves both hosts. Never
/// throws — analysis failures return a [SnapshotBundle.failed].
class SnapshotAnalyzer {
  const SnapshotAnalyzer({this.options = const GraphAnalysisOptions()});

  static const _log = 'radarWorkbench.analyzer';

  final GraphAnalysisOptions options;

  Future<SnapshotBundle> fromGraph(
    HeapGraphView graph, {
    String label = '',
  }) async {
    final capturedAt = DateTime.now();
    try {
      final histogram = graph.classHistogram();
      final result = await compute(_analyzeGraph, (graph, options));
      return SnapshotBundle(
        capturedAt: capturedAt,
        label: label,
        histogram: histogram,
        analysisResult: result,
      );
    } catch (e, s) {
      developer.log('fromGraph failed', name: _log, error: e, stackTrace: s);
      return SnapshotBundle.failed(
        capturedAt: capturedAt,
        label: label,
        message: 'Analysis failed — see console for details.',
      );
    }
  }

  Future<SnapshotBundle> fromBytes(Uint8List bytes, {String label = ''}) async {
    final capturedAt = DateTime.now();
    try {
      final res = await compute(_analyzeBytes, (bytes, options));
      return SnapshotBundle(
        capturedAt: capturedAt,
        label: label,
        histogram: res.histogram,
        analysisResult: res.result,
      );
    } catch (e, s) {
      developer.log('fromBytes failed', name: _log, error: e, stackTrace: s);
      return SnapshotBundle.failed(
        capturedAt: capturedAt,
        label: label,
        message: 'Snapshot parse/analysis failed — see console for details.',
      );
    }
  }
}

// Top-level entry points required by [compute].

GraphAnalysisResult _analyzeGraph((HeapGraphView, GraphAnalysisOptions) req) =>
    const GraphLeakAnalyzer().analyze(req.$1, req.$2);

({List<ClassCount> histogram, GraphAnalysisResult result}) _analyzeBytes(
  (Uint8List, GraphAnalysisOptions) req,
) {
  final graph = heapGraphFromBytes(req.$1);
  return (
    histogram: graph.classHistogram(),
    result: const GraphLeakAnalyzer().analyze(graph, req.$2),
  );
}
