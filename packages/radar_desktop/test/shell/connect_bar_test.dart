import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/vm_service_uri_connection.dart';
import 'package:radar_desktop/src/shell/connect_bar.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// Minimal fake covering only the surface [VmServiceUriConnection] touches —
/// same recipe as `test/seams/vm_service_uri_connection_test.dart`.
class _FakeVmService implements VmService {
  _FakeVmService({VM? vm}) : vm = vm ?? _cannedVm;

  final VM vm;

  @override
  Future<VM> getVM() async => vm;

  @override
  Future<void> get onDone => Completer<void>().future;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _cannedVm = VM(
  name: 'FakeVM',
  isolates: [IsolateRef(id: 'iso-1', name: 'main', number: '1')],
);

Future<void> _pump(WidgetTester tester, VmServiceUriConnection connection) {
  return tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: ConnectBar(connection: connection)),
    ),
  );
}

void main() {
  group('ConnectBar', () {
    testWidgets('disconnected: shows the URI field and a disabled Connect '
        'button', (tester) async {
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );
      addTearDown(connection.dispose);

      await _pump(tester, connection);

      expect(find.byType(TextField), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('disconnected: Connect enables once the field is non-empty', (
      tester,
    ) async {
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );
      addTearDown(connection.dispose);

      await _pump(tester, connection);
      await tester.enterText(find.byType(TextField), 'ws://127.0.0.1:1/ws');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('entering a URI and tapping Connect connects and swaps to '
        'the Disconnect button', (tester) async {
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );
      addTearDown(connection.dispose);

      await _pump(tester, connection);
      await tester.enterText(
        find.byType(TextField),
        'ws://127.0.0.1:1234/AUTH=/ws',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      // Not pumpAndSettle: the URI TextField's cursor-blink Timer keeps a
      // frame scheduled forever once focused, so settle() would hang. A
      // couple of zero-duration pumps is enough to drain the connect
      // microtask chain (connectFn's future, then getVM's).
      await tester.pump();
      await tester.pump();

      expect(connection.state.phase, RadarConnectionPhase.connected);
      expect(find.widgetWithText(OutlinedButton, 'Disconnect'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('tapping Disconnect returns to disconnected and the URI '
        'field reappears', (tester) async {
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );
      addTearDown(connection.dispose);
      await connection.connect('ws://127.0.0.1:1234/AUTH=/ws');

      await _pump(tester, connection);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
      await tester.pump();
      await tester.pump();

      expect(connection.state.phase, RadarConnectionPhase.disconnected);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a connect failure shows the inline error and stays '
        'disconnected', (tester) async {
      final connection = VmServiceUriConnection(
        connect: (_) async => throw Exception('boom'),
      );
      addTearDown(connection.dispose);

      await _pump(tester, connection);
      await tester.enterText(find.byType(TextField), 'ws://127.0.0.1:1/ws');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pump();
      await tester.pump();

      expect(connection.state.phase, RadarConnectionPhase.disconnected);
      expect(find.textContaining('boom'), findsOneWidget);
    });
  });
}
