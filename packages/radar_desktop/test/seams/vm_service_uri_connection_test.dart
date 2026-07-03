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
  });
}
