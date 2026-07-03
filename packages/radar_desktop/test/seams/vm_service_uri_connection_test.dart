import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/vm_service_uri_connection.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// Minimal fake covering only the surface [VmServiceUriConnection] touches.
/// `implements VmService` + a `noSuchMethod` override lets a concrete class
/// stand in for the interface without implementing its full (huge) API.
class _FakeVmService implements VmService {
  _FakeVmService({VM? vm}) : vm = vm ?? _cannedVm;

  final VM vm;
  final Completer<void> doneCompleter = Completer<void>();
  bool disposeCalled = false;

  @override
  Future<VM> getVM() async => vm;

  @override
  Future<void> get onDone => doneCompleter.future;

  @override
  Future<void> dispose() async {
    disposeCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _cannedVm = VM(
  name: 'FakeVM',
  isolates: [IsolateRef(id: 'iso-1', name: 'main', number: '1')],
);

void main() {
  group('VmServiceUriConnection', () {
    test('starts disconnected with no handles', () {
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );
      expect(connection.state.phase, RadarConnectionPhase.disconnected);
      expect(connection.vmService, isNull);
      expect(connection.isolateRef, isNull);
      expect(connection.lastError, isNull);
    });

    test('connect succeeds: connected phase, handles set, notifies', () async {
      final fake = _FakeVmService();
      var notified = 0;
      final connection = VmServiceUriConnection(connect: (_) async => fake)
        ..addListener(() => notified++);

      await connection.connect('ws://x');

      expect(connection.state.phase, RadarConnectionPhase.connected);
      expect(connection.vmService, same(fake));
      expect(connection.isolateRef, isNotNull);
      expect(connection.state.vmName, 'FakeVM');
      expect(connection.state.isolateName, 'main');
      expect(notified, greaterThan(0));
    });

    test('picks the isolate named main among several', () async {
      final vm = VM(
        name: 'MultiVM',
        isolates: [
          IsolateRef(id: 'iso-0', name: 'other', number: '0'),
          IsolateRef(id: 'iso-1', name: 'main', number: '1'),
        ],
      );
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(vm: vm),
      );

      await connection.connect('ws://x');

      expect(connection.state.isolateName, 'main');
    });

    test('falls back to the first isolate when none is named main', () async {
      final vm = VM(
        name: 'SoloVM',
        isolates: [IsolateRef(id: 'iso-0', name: 'only', number: '0')],
      );
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(vm: vm),
      );

      await connection.connect('ws://x');

      expect(connection.state.isolateName, 'only');
    });

    test('connect failure: disconnected + lastError set', () async {
      final connection = VmServiceUriConnection(
        connect: (_) async => throw Exception('boom'),
      );

      await connection.connect('ws://x');

      expect(connection.state.phase, RadarConnectionPhase.disconnected);
      expect(connection.lastError, contains('boom'));
      expect(connection.vmService, isNull);
      expect(connection.isolateRef, isNull);
    });

    test('a VM with no isolates fails the connect', () async {
      final vm = VM(name: 'EmptyVM', isolates: const []);
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(vm: vm),
      );

      await connection.connect('ws://x');

      expect(connection.state.phase, RadarConnectionPhase.disconnected);
      expect(connection.lastError, isNotNull);
    });

    test('onDone firing after connect flips back to disconnected', () async {
      final fake = _FakeVmService();
      final connection = VmServiceUriConnection(connect: (_) async => fake);
      await connection.connect('ws://x');
      expect(connection.state.phase, RadarConnectionPhase.connected);

      fake.doneCompleter.complete();
      await Future<void>.delayed(Duration.zero);

      expect(connection.state.phase, RadarConnectionPhase.disconnected);
      expect(connection.vmService, isNull);
      expect(connection.isolateRef, isNull);
    });

    test('disconnect() disposes the vm service and clears state', () async {
      final fake = _FakeVmService();
      final connection = VmServiceUriConnection(connect: (_) async => fake);
      await connection.connect('ws://x');

      await connection.disconnect();

      expect(fake.disposeCalled, isTrue);
      expect(connection.state.phase, RadarConnectionPhase.disconnected);
      expect(connection.vmService, isNull);
      expect(connection.isolateRef, isNull);
    });

    test('disconnect() before any connect is a safe no-op', () async {
      final connection = VmServiceUriConnection(
        connect: (_) async => _FakeVmService(),
      );

      await connection.disconnect();

      expect(connection.state.phase, RadarConnectionPhase.disconnected);
    });

    test('disconnect during an in-flight connect wins the race: final phase '
        'stays disconnected and the orphaned VmService is disposed', () async {
      final fake = _FakeVmService();
      final connectGate = Completer<void>();
      final connection = VmServiceUriConnection(
        connect: (_) async {
          await connectGate.future;
          return fake;
        },
      );

      final connectFuture = connection.connect('ws://x');
      await connection.disconnect();
      connectGate.complete();
      await connectFuture;

      expect(connection.state.phase, RadarConnectionPhase.disconnected);
      expect(connection.vmService, isNull);
      expect(fake.disposeCalled, isTrue);
    });

    test(
      'dispose() disposes the vm service and suppresses late notifies',
      () async {
        final fake = _FakeVmService();
        final connection = VmServiceUriConnection(connect: (_) async => fake);
        await connection.connect('ws://x');

        connection.dispose();
        expect(fake.disposeCalled, isTrue);

        // Without the generation bump + `_disposed` guard, this onDone firing
        // after dispose would call notifyListeners() on an already-disposed
        // ChangeNotifier, which throws. Completing it here (and letting the
        // microtask queue drain) must not raise or leave a pending exception.
        fake.doneCompleter.complete();
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'a manual disconnect fires exactly one disconnected notification',
      () async {
        final fake = _FakeVmService();
        var notified = 0;
        final connection = VmServiceUriConnection(connect: (_) async => fake)
          ..addListener(() => notified++);

        await connection.connect('ws://x');
        final notifiedAfterConnect = notified;

        await connection.disconnect();

        expect(notified - notifiedAfterConnect, 1);

        // onDone completing after a manual disconnect must not add another
        // notification: the generation bump makes the old onDone a no-op.
        fake.doneCompleter.complete();
        await Future<void>.delayed(Duration.zero);
        expect(notified - notifiedAfterConnect, 1);
      },
    );

    test('connect() while already connected is a no-op', () async {
      var callCount = 0;
      final fake = _FakeVmService();
      final connection = VmServiceUriConnection(
        connect: (_) async {
          callCount++;
          return fake;
        },
      );

      await connection.connect('ws://x');
      await connection.connect('ws://x');

      expect(callCount, 1);
      expect(connection.state.phase, RadarConnectionPhase.connected);
    });
  });
}
