import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/app/desktop_view.dart';
import 'package:radar_desktop/src/screens/clusters_screen.dart';
import 'package:radar_desktop/src/shell/desktop_rail.dart';
import 'package:radar_desktop/src/shell/desktop_shell.dart';
import 'package:radar_desktop/src/tools/tools_controller.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// In-memory [ToolConfigStore] fake — no real fs/path_provider.
class _FakeToolConfigStore implements ToolConfigStore {
  @override
  Future<ToolConfig> read() async => const ToolConfig({});

  @override
  Future<void> write(ToolConfig config) async {}
}

/// A [ToolsController] whose probe never touches the real filesystem — keeps
/// `DesktopShell`'s `unawaited(_tools.load())` fast and deterministic.
ToolsController _fakeTools() => ToolsController(
  probe: ToolProbe(
    exists: (_) => false,
    run: (_, __) async => (exitCode: 1, stdout: '', stderr: 'not found'),
    commonLocations: (_) => const [],
  ),
  store: _FakeToolConfigStore(),
);

void main() {
  testWidgets('the Leak clusters rail item is present and reports taps', (
    tester,
  ) async {
    DesktopView? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(
          body: DesktopRail(
            current: DesktopView.dumps,
            connected: false,
            onSelect: (v) => tapped = v,
          ),
        ),
      ),
    );
    expect(find.text('Leak clusters'), findsOneWidget);
    await tester.ensureVisible(find.text('Leak clusters'));
    await tester.tap(find.text('Leak clusters'));
    expect(tapped, DesktopView.clusters);
  });

  testWidgets('the shell routes the Leak clusters destination to '
      'ClustersScreen/LeakClustersView even while offline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DesktopShell(tools: _fakeTools())),
    );

    await tester.ensureVisible(find.text('Leak clusters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leak clusters'));
    await tester.pumpAndSettle();

    expect(find.byType(ClustersScreen), findsOneWidget);
    expect(find.byType(LeakClustersView), findsOneWidget);
  });
}
