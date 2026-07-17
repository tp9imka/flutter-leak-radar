import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:radar_desktop/src/seams/file_snapshot_store.dart';
import 'package:radar_desktop/src/shell/desktop_shell.dart';
import 'package:radar_desktop/src/tools/tools_controller.dart';
import 'package:radar_desktop/src/workspace/workspace_controller.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

ToolsController _fakeTools() => ToolsController(
  probe: ToolProbe(
    exists: (_) => false,
    run: (_, __) async => (exitCode: 1, stdout: '', stderr: 'not found'),
    commonLocations: (_) => const [],
  ),
  store: _FakeToolConfigStore(),
);

class _FakeToolConfigStore implements ToolConfigStore {
  @override
  Future<ToolConfig> read() async => const ToolConfig({});
  @override
  Future<void> write(ToolConfig config) async {}
}

void main() {
  testWidgets('surfaces a newer-schema restore refusal as a banner', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('radar_shell_refusal');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    File(p.join(dir.path, 'radar_desktop_session.json')).writeAsStringSync(
      jsonEncode({
        'version': kSessionSchemaVersion + 1,
        'bundles': const <Object?>[],
        'selectedIds': const <Object?>[],
        'view': 'leakClusters',
      }),
    );
    final workspace = WorkspaceController(
      store: FileSnapshotStore(directory: () async => dir),
    );
    // The real file read must run in the real async zone (not testWidgets'
    // FakeAsync). restore() is idempotent, so the shell's own initState call is
    // a no-op and never re-reads the file inside FakeAsync.
    await tester.runAsync(workspace.restore);

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopShell(tools: _fakeTools(), workspace: workspace),
      ),
    );
    await tester.pump();

    expect(find.byType(RadarBanner), findsOneWidget);
    expect(find.textContaining('newer'), findsOneWidget);
    expect(find.text('Start new'), findsOneWidget);
  });
}
