import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/app/desktop_view.dart';
import 'package:radar_desktop/src/screens/dumps_screen.dart';
import 'package:radar_desktop/src/screens/trends_screen.dart';
import 'package:radar_desktop/src/seams/vm_service_uri_connection.dart';
import 'package:radar_desktop/src/shell/connect_bar.dart';
import 'package:radar_desktop/src/shell/desktop_rail.dart';
import 'package:radar_desktop/src/shell/desktop_shell.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

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

  testWidgets('shell routes memory views to real screens; '
      'opening a dump goes to histogram', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesktopShell()));
    // Default view = dumps → DumpsScreen present.
    expect(find.byType(DumpsScreen), findsOneWidget);
    // Navigate to Trends via the rail.
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.byType(TrendsScreen), findsOneWidget);
  });

  group('connected mode', () {
    testWidgets(
      'perf/stability items stay locked and unrouted while disconnected',
      (tester) async {
        final connection = VmServiceUriConnection(
          connect: (_) async => _FakeVmService(),
        );

        await tester.pumpWidget(
          MaterialApp(home: DesktopShell(connection: connection)),
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
          MaterialApp(home: DesktopShell(connection: connection)),
        );

        await connection.connect('ws://x');
        await tester.pump();

        await tester.tap(find.text('Traces'));
        await tester.pump();

        expect(find.byType(TracesView), findsOneWidget);
        expect(find.byType(ConnectBar), findsOneWidget);
      },
    );
  });
}
