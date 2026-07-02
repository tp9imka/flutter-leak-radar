import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// Exports a snapshot bundle as a JSON file via a native save dialog.
class DesktopSnapshotExporter implements SnapshotExporter {
  const DesktopSnapshotExporter();

  @override
  Future<void> export(SnapshotBundle bundle, {String? suggestedName}) async {
    final base = suggestedName ?? 'heap_${bundle.id}_${bundle.label}';
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final location = await getSaveLocation(
      suggestedName: '$safe.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null) return; // user cancelled
    final json = const JsonEncoder.withIndent('  ').convert(bundle.toJson());
    await File(location.path).writeAsString(json);
  }
}
