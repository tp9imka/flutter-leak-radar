import 'dart:developer' as developer;

import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// Captures a heap snapshot from the connected app's VM service and hands the
/// parsed graph to the shared [SnapshotAnalyzer]. Never throws.
class DevToolsSnapshotSource implements SnapshotSource {
  const DevToolsSnapshotSource(this._connection, this._analyzer);

  final RadarConnection _connection;
  final SnapshotAnalyzer _analyzer;

  static const _log = 'leakRadarDevTools.snapshot';

  @override
  Future<SnapshotBundle> capture({String label = ''}) async {
    final svc = _connection.vmService;
    final iso = _connection.isolateRef;
    if (svc == null || iso == null) {
      return SnapshotBundle.failed(
        label: label,
        message: 'Not connected to a running app.',
      );
    }
    try {
      final graph = await HeapSnapshotGraph.getSnapshot(svc, iso);
      return _analyzer.fromGraph(VmSnapshotGraphView(graph), label: label);
    } catch (e, s) {
      developer.log('capture failed', name: _log, error: e, stackTrace: s);
      return SnapshotBundle.failed(
        label: label,
        message: 'Snapshot capture failed — see console for details.',
      );
    }
  }
}
