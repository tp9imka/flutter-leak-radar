import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/desktop_memory_poll.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// Minimal fake covering only [VmService.getMemoryUsage]. `implements
/// VmService` + `noSuchMethod` stands in for the huge interface — the same
/// recipe as `test/seams/desktop_perf_call_test.dart`.
class _FakeVmService implements VmService {
  _FakeVmService({this.usage});

  final MemoryUsage? usage;
  String? lastIsolateId;

  @override
  Future<MemoryUsage> getMemoryUsage(String isolateId) async {
    lastIsolateId = isolateId;
    return usage!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Minimal fake [RadarConnection]: a plain data holder wired through
/// [ChangeNotifier] to satisfy [Listenable].
class _FakeConnection extends ChangeNotifier implements RadarConnection {
  _FakeConnection({this.vmService, this.isolateRef});

  @override
  final VmService? vmService;

  @override
  final IsolateRef? isolateRef;

  @override
  RadarConnectionState get state =>
      const RadarConnectionState(phase: RadarConnectionPhase.connected);
}

final _isolateRef = IsolateRef(id: 'iso-1', name: 'main', number: '1');

void main() {
  group('desktopMemoryPoll', () {
    test('reads heapUsage and externalUsage off the isolate', () async {
      final fake = _FakeVmService(
        usage: MemoryUsage(heapUsage: 1000, externalUsage: 250),
      );
      final connection = _FakeConnection(
        vmService: fake,
        isolateRef: _isolateRef,
      );

      final sample = await desktopMemoryPoll(connection);

      expect(sample.heapUsage, 1000);
      expect(sample.externalUsage, 250);
      expect(fake.lastIsolateId, 'iso-1');
    });

    test('a null vmService throws MemoryPollUnavailableException', () {
      final connection = _FakeConnection(isolateRef: _isolateRef);

      expect(
        () => desktopMemoryPoll(connection),
        throwsA(isA<MemoryPollUnavailableException>()),
      );
    });

    test('a null isolateRef throws MemoryPollUnavailableException', () {
      final connection = _FakeConnection(vmService: _FakeVmService());

      expect(
        () => desktopMemoryPoll(connection),
        throwsA(isA<MemoryPollUnavailableException>()),
      );
    });

    test(
      'a missing field (parsed as -1) throws — never fabricated as 0',
      () async {
        // vm_service defaults an absent field to -1; that is not-measured, not
        // a real zero. The parsed-or-unmeasured rule: it must surface as a gap.
        final fake = _FakeVmService(
          usage: MemoryUsage(heapUsage: -1, externalUsage: 250),
        );
        final connection = _FakeConnection(
          vmService: fake,
          isolateRef: _isolateRef,
        );

        await expectLater(
          desktopMemoryPoll(connection),
          throwsA(isA<MemoryPollUnavailableException>()),
        );
      },
    );

    test(
      'memoryPollFor binds a connection into a MemoryPoll closure',
      () async {
        final fake = _FakeVmService(
          usage: MemoryUsage(heapUsage: 42, externalUsage: 7),
        );
        final connection = _FakeConnection(
          vmService: fake,
          isolateRef: _isolateRef,
        );

        final poll = memoryPollFor(connection);
        final sample = await poll();

        expect(sample.heapUsage, 42);
        expect(sample.externalUsage, 7);
      },
    );
  });
}
