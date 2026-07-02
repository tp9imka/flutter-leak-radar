import 'package:radar_workbench/radar_workbench.dart';

import '../util/web_download.dart';

/// Exports a bundle as a browser download of its JSON.
class DevToolsSnapshotExporter implements SnapshotExporter {
  const DevToolsSnapshotExporter();

  @override
  Future<void> export(SnapshotBundle bundle, {String? suggestedName}) async {
    final base = suggestedName ?? 'heap_${bundle.id}_${bundle.label}';
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    downloadJson('$safe.json', bundle.toJson());
  }
}
