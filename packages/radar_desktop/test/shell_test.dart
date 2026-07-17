import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/app/desktop_view.dart';
import 'package:radar_desktop/src/onboarding/first_run_guide_controller.dart';
import 'package:radar_desktop/src/screens/dumps_screen.dart';
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

/// In-memory [FirstRunStore] fake — no real fs/path_provider, mirrors
/// `test/onboarding/first_run_guide_controller_test.dart`'s fake.
class _FakeFirstRunStore implements FirstRunStore {
  bool seen = false;
  int markSeenCount = 0;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async {
    seen = true;
    markSeenCount++;
  }
}

/// A [FirstRunGuideController] backed by an already-"seen" in-memory
/// store. Injected into every shell test that doesn't exercise the
/// guide itself, so `DesktopShell`'s default `FileFirstRunStore` (which
/// needs a real `path_provider` platform channel) never runs and the
/// guide overlay never auto-opens and steals taps meant for the rail
/// or screens beneath it.
FirstRunGuideController _seenGuide() =>
    FirstRunGuideController(store: _FakeFirstRunStore()..seen = true);

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
      MaterialApp(
        home: DesktopShell(tools: _fakeTools(), guide: _seenGuide()),
      ),
    );
    // Default view = dumps → DumpsScreen present.
    expect(find.byType(DumpsScreen), findsOneWidget);
    // Navigate to Trends via the rail.
    await tester.tap(find.text('Trends'));
    // `pump`, not `pumpAndSettle`: the shell now always mounts
    // `FirstRunGuide`, whose glow-pulse `AnimationController` repeats
    // forever once built — regardless of the guide being closed — so
    // `pumpAndSettle` never settles and times out. One frame is enough
    // to reflect the rail-tap's `setState`.
    await tester.pump();
    expect(find.byType(TrendsScreen), findsOneWidget);
  });

  testWidgets(
    'the Tools destination routes to ToolsScreen even while offline',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShell(tools: _fakeTools(), guide: _seenGuide()),
        ),
      );

      // SETUP sits below four other groups, off-screen at the default
      // test surface height — scroll it into view before tapping.
      // `pump` (not `pumpAndSettle` — see the note above) with enough
      // time for the scroll-into-view animation to finish.
      await tester.ensureVisible(find.text('Tools'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Tools'));
      await tester.pump();

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
            home: DesktopShell(
              connection: connection,
              tools: _fakeTools(),
              guide: _seenGuide(),
            ),
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
            home: DesktopShell(
              connection: connection,
              tools: _fakeTools(),
              guide: _seenGuide(),
            ),
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
            home: DesktopShell(
              connection: connection,
              tools: _fakeTools(),
              guide: _seenGuide(),
            ),
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

    testWidgets('disposing the shell does not dispose an injected connection', (
      tester,
    ) async {
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShell(connection: connection, guide: _seenGuide()),
        ),
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

        await tester.pumpWidget(
          MaterialApp(
            home: DesktopShell(tools: tools, guide: _seenGuide()),
          ),
        );

        // Replace the tree so DesktopShell.dispose() runs.
        await tester.pumpWidget(const SizedBox.shrink());

        // An injected ToolsController belongs to the caller — the shell
        // must remove its own listener but leave the controller itself
        // usable, same contract as an injected connection above.
        expect(() => tools.addListener(() {}), returnsNormally);
      },
    );
  });

  group('first-run guide', () {
    testWidgets(
      'shows the welcome step over the shell when the guide is unseen',
      (tester) async {
        final guide = FirstRunGuideController(store: _FakeFirstRunStore());

        await tester.pumpWidget(
          MaterialApp(
            home: DesktopShell(tools: _fakeTools(), guide: guide),
          ),
        );
        // Two pumps: one to let the fake store's `hasSeen()` future
        // resolve, one to render the `setState` that `load()` triggers.
        await tester.pump();
        await tester.pump();

        expect(find.text('Welcome to Radar Desktop'), findsOneWidget);
      },
    );

    testWidgets('shows nothing when the guide has already been seen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShell(tools: _fakeTools(), guide: _seenGuide()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Welcome to Radar Desktop'), findsNothing);
    });

    testWidgets('the chrome "?" button re-opens the welcome step', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShell(tools: _fakeTools(), guide: _seenGuide()),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Welcome to Radar Desktop'), findsNothing);

      await tester.tap(find.byTooltip('Show guide'));
      // The button sits inside `DragToMoveArea` — same double-tap arena
      // caveat as `desktop_window_chrome_test.dart`'s reopen-guide test:
      // the tap only resolves once the double-tap window elapses.
      await tester.pump(kDoubleTapTimeout);

      expect(find.text('Welcome to Radar Desktop'), findsOneWidget);
    });
  });
}
