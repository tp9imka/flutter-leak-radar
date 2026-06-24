// test/engine/vm_heap_probe_throttle_test.dart
//
// Task 1.3 — verify maxRetainingPathRequests throttle in VmHeapProbe.
// Confirms that:
//   (a) retainingPath returns null once the per-cycle budget is exhausted.
//   (b) the counter resets after a new capture() call.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';
import 'package:vm_service/vm_service.dart';

// ---------------------------------------------------------------------------
// Fake VM service — returns a single instance with a trivial retaining path.
// ---------------------------------------------------------------------------

final _fakeClassRef = ClassRef(id: 'classes/1', name: 'Dummy');

ObjRef _fakeInstance() => InstanceRef(
  id: 'objects/1',
  kind: 'PlainInstance',
  classRef: _fakeClassRef,
);

class _ThrottleFakeService extends Fake implements VmService {
  int retainingPathCalls = 0;

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) async {
    final member = ClassHeapStats()
      ..classRef = _fakeClassRef
      ..instancesCurrent = 1
      ..bytesCurrent = 64;
    return AllocationProfile()..members = [member];
  }

  @override
  Future<InstanceSet> getInstances(
    String isolateId,
    String classId,
    int limit, {
    bool? includeSubclasses,
    bool? includeImplementers,
    String? idZoneId,
  }) async => InstanceSet()..instances = [_fakeInstance()];

  @override
  Future<RetainingPath> getRetainingPath(
    String isolateId,
    String targetId,
    int limit, {
    String? idZoneId,
  }) async {
    retainingPathCalls++;
    final el = RetainingObject()..value = _fakeInstance();
    return RetainingPath()
      ..gcRootType = 'user-global'
      ..elements = [el];
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _ThrottleFakeService fakeService;
  late ClassRef fakeClassRef;

  setUp(() {
    fakeService = _ThrottleFakeService();
    fakeClassRef = ClassRef(id: 'classes/1', name: 'Dummy');
  });

  group('VmHeapProbe maxRetainingPathRequests throttle', () {
    test(
      'retainingPath returns null after maxRetainingPathRequests per cycle',
      () async {
        final probe = VmHeapProbe(maxRetainingPathRequests: 2);
        probe.debugInjectServiceAndCache(
          fakeService,
          isolateId: 'isolates/1',
          classRefCache: {
            'A': fakeClassRef,
            'B': fakeClassRef,
            'C': fakeClassRef,
          },
        );

        // Act: request 3 paths; limit is 2.
        final p1 = await probe.retainingPath('A');
        final p2 = await probe.retainingPath('B');
        final p3 = await probe.retainingPath('C'); // should be throttled → null

        expect(p1, isNotNull);
        expect(p2, isNotNull);
        expect(p3, isNull); // throttled
      },
    );

    test('retainingPath counter resets after capture', () async {
      final probe = VmHeapProbe(maxRetainingPathRequests: 1);
      probe.debugInjectServiceAndCache(
        fakeService,
        isolateId: 'isolates/1',
        classRefCache: {'A': fakeClassRef},
      );

      final p1 = await probe.retainingPath('A'); // allowed
      final p2 = await probe.retainingPath('A'); // throttled
      // Simulate a new capture cycle.
      await probe.capture(forceGc: false); // resets counter
      final p3 = await probe.retainingPath('A'); // allowed again

      expect(p1, isNotNull);
      expect(p2, isNull);
      expect(p3, isNotNull);
    });

    test('RPC is not called for throttled requests', () async {
      final probe = VmHeapProbe(maxRetainingPathRequests: 1);
      probe.debugInjectServiceAndCache(
        fakeService,
        isolateId: 'isolates/1',
        classRefCache: {'A': fakeClassRef, 'B': fakeClassRef},
      );

      await probe.retainingPath('A'); // allowed, calls RPC
      await probe.retainingPath('B'); // throttled, must NOT call RPC

      expect(fakeService.retainingPathCalls, 1);
    });
  });
}
