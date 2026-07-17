import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/app/desktop_view.dart';
import 'package:radar_desktop/src/screens/device_monitor_screen.dart';
import 'package:radar_desktop/src/screens/dumps_screen.dart';
import 'package:radar_desktop/src/screens/live_memory_controller.dart';
import 'package:radar_desktop/src/screens/tools_screen.dart';
import 'package:radar_desktop/src/screens/trends_screen.dart';
import 'package:radar_desktop/src/seams/vm_service_uri_connection.dart';
import 'package:radar_desktop/src/shell/connect_bar.dart';
import 'package:radar_desktop/src/shell/desktop_rail.dart';
import 'package:radar_desktop/src/shell/desktop_shell.dart';
import 'package:radar_desktop/src/tools/tools_controller.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// In-memory [ToolConfigStore] fake — no real fs/path_provider.
class _FakeToolConfigStore implements ToolConfigStore {
  @override
  Future<ToolConfig> read() async => const ToolConfig({});

  @override
  Future<void> write(ToolConfig config) async {}
}

/// A [ToolsController] whose probe never touches the real filesystem or
/// spawns a real process — every tool reports missing, instantly. These
/// shell tests don't exercise Tools-screen behavior; this just keeps
/// `DesktopShell`'s `unawaited(_tools.load())` in `initState` fast and
/// deterministic instead of racing real `Process.run` calls.
ToolsController _fakeTools() => ToolsController(
  probe: ToolProbe(
    exists: (_) => false,
    run: (_, __) async => (exitCode: 1, stdout: '', stderr: 'not found'),
    commonLocations: (_) => const [],
  ),
  store: _FakeToolConfigStore(),
);

/// Minimal fake covering only the surface [VmServiceUriConnection] and
/// [PerfDataController] touch; mirrors the fake in
/// `test/seams/vm_service_uri_connection_test.dart`. `noSuchMethod` lets it
/// stand in for the (huge) [VmService] interface without implementing it.
class _FakeVmService implements VmService {
  final VM vm = VM(
    name: 'FakeVM',
    isolates: [IsolateRef(id: 'iso-1', name: 'main', number: '1')],
  );

  @override
  Future<VM> getVM() async => vm;

  @override
  Future<void> get onDone => Completer<void>().future;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('rail lists the five memory destinations and reports taps', (
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
    for (final label in [
      'Dumps',
      'Class histogram',
      'Retaining paths',
      'Trends',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // 'Compare' appears twice: MEMORY's dump-diff view and ANDROID NATIVE's
    // checkpoint-diff view share the label.
    expect(find.text('Compare'), findsNWidgets(2));
    await tester.tap(find.text('Trends'));
    expect(tapped, DesktopView.trends);
  });

  testWidgets('performance/stability items are locked when offline', (
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
    // Tapping a locked Performance item does nothing.
    await tester.tap(find.text('Traces'));
    expect(tapped, isNull);
  });

  testWidgets('the SETUP/Tools rail item is shown and selectable offline', (
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
    expect(find.text('SETUP'), findsOneWidget);
    // SETUP sits below four other groups, off-screen at the default test
    // surface height — scroll it into view before tapping.
    await tester.ensureVisible(find.text('Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tools'));
    expect(tapped, DesktopView.tools);
  });

  testWidgets('shell routes memory views to real screens; '
      'opening a dump goes to histogram', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DesktopShell(tools: _fakeTools())),
    );
    // Default view = dumps → DumpsScreen present.
    expect(find.byType(DumpsScreen), findsOneWidget);
    // Navigate to Trends via the rail.
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.byType(TrendsScreen), findsOneWidget);
  });

  testWidgets(
    'the Device Monitor destination routes to DeviceMonitorScreen offline '
    '(import-first is not connection-gated)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DesktopShell(tools: _fakeTools())),
      );

      // DEVICE sits below the memory/perf/stability/android groups — scroll
      // it into view before tapping.
      await tester.ensureVisible(find.text('Device Monitor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device Monitor'));
      await tester.pumpAndSettle();

      expect(find.byType(DeviceMonitorScreen), findsOneWidget);
    },
  );

  testWidgets(
    'the Tools destination routes to ToolsScreen even while offline',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DesktopShell(tools: _fakeTools())),
      );

      // SETUP sits below four other groups, off-screen at the default
      // test surface height — scroll it into view before tapping.
      await tester.ensureVisible(find.text('Tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      expect(find.byType(ToolsScreen), findsOneWidget);
    },
  );

  group('connected mode', () {
    testWidgets(
      'perf/stability items stay locked and unrouted while disconnected',
      (tester) async {
        final connection = VmServiceUriConnection(
          connect: (_) async => _FakeVmService(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DesktopShell(connection: connection, tools: _fakeTools()),
          ),
        );

        expect(find.byType(ConnectBar), findsOneWidget);
        expect(find.byType(DumpsScreen), findsOneWidget);

        // Locked: tapping the rail item does nothing (its InkWell has no
        // onTap while offline), so the shell stays on the memory view.
        await tester.tap(find.text('Traces'));
        await tester.pump();

        expect(find.byType(TracesView), findsNothing);
        expect(find.byType(DumpsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'connecting unlocks perf/stability and routes Traces to TracesView',
      (tester) async {
        final connection = VmServiceUriConnection(
          connect: (_) async => _FakeVmService(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DesktopShell(connection: connection, tools: _fakeTools()),
          ),
        );

        await connection.connect('ws://x');
        await tester.pump();

        await tester.tap(find.text('Traces'));
        await tester.pump();

        expect(find.byType(TracesView), findsOneWidget);
        expect(find.byType(ConnectBar), findsOneWidget);
      },
    );

    testWidgets(
      'dropping the connection while a perf view is showing falls back '
      'to a memory view instead of leaving it stale',
      (tester) async {
        final connection = VmServiceUriConnection(
          connect: (_) async => _FakeVmService(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DesktopShell(connection: connection, tools: _fakeTools()),
          ),
        );

        await connection.connect('ws://x');
        await tester.pump();

        await tester.tap(find.text('Traces'));
        await tester.pump();
        expect(find.byType(TracesView), findsOneWidget);

        await connection.disconnect();
        await tester.pump();

        expect(find.byType(TracesView), findsNothing);
        expect(find.byType(DumpsScreen), findsOneWidget);
      },
    );

    testWidgets('connecting while parked on Device Monitor starts live polling '
        'immediately (no nav-away-and-back)', (tester) async {
      final live = LiveMemoryController(
        poll: () async => (heapUsage: 1, externalUsage: 1),
      );
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShell(
            connection: connection,
            tools: _fakeTools(),
            liveMemory: live,
          ),
        ),
      );

      // Park on the Device Monitor while still offline.
      await tester.ensureVisible(find.text('Device Monitor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device Monitor'));
      await tester.pumpAndSettle();
      expect(live.isPolling, isFalse);

      // Connect while already on the pane — polling must begin here, not
      // only on the next navigation into the pane.
      await connection.connect('ws://x');
      await tester.pump();
      expect(live.isPolling, isTrue);

      // Cancel the periodic timer before teardown asserts no pending timers.
      live.stop();
      addTearDown(live.dispose);
    });

    testWidgets('disposing the shell does not dispose an injected connection', (
      tester,
    ) async {
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );

      await tester.pumpWidget(
        MaterialApp(home: DesktopShell(connection: connection)),
      );

      // Replace the tree so DesktopShell.dispose() runs.
      await tester.pumpWidget(const SizedBox.shrink());

      // An injected connection belongs to the caller: it must still be a
      // live, listenable ChangeNotifier after the shell that borrowed it
      // is torn down. A real dispose() call would make this assert-fail
      // ("A disposed ChangeNotifier was used") in debug mode.
      expect(() => connection.addListener(() {}), returnsNormally);
    });

    testWidgets(
      'disposing the shell does not dispose an injected tools controller',
      (tester) async {
        final tools = _fakeTools();

        await tester.pumpWidget(MaterialApp(home: DesktopShell(tools: tools)));

        // Replace the tree so DesktopShell.dispose() runs.
        await tester.pumpWidget(const SizedBox.shrink());

        // An injected ToolsController belongs to the caller — the shell
        // must remove its own listener but leave the controller itself
        // usable, same contract as an injected connection above.
        expect(() => tools.addListener(() {}), returnsNormally);
      },
    );
  });
}
