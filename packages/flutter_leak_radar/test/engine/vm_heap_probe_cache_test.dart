// test/engine/vm_heap_probe_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';
import 'package:vm_service/vm_service.dart';

/// Minimal fake VmService that counts getAllocationProfile calls and returns
/// a single-member profile with class 'HomeBloc'.
class _CountingFakeService extends Fake implements VmService {
  int allocationProfileCalls = 0;

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) async {
    allocationProfileCalls++;
    final classRef = ClassRef(
      id: 'classes/1',
      name: 'HomeBloc',
      library: LibraryRef(id: 'libs/1', name: 'test', uri: 'package:test/test.dart'),
    );
    final member = ClassHeapStats()
      ..classRef = classRef
      ..instancesCurrent = 3
      ..bytesCurrent = 128;
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
  }) async {
    return InstanceSet()..instances = [];
  }
}

void main() {
  group('VmHeapProbe class-ref cache', () {
    test(
      'retainingPath does not call getAllocationProfile when cache is warm',
      () async {
        final probe = VmHeapProbe();
        final fakeService = _CountingFakeService();
        final fakeClassRef = ClassRef(id: 'classes/1', name: 'HomeBloc');

        // Inject a warm cache entry — should skip getAllocationProfile entirely.
        probe.debugInjectServiceAndCache(
          fakeService,
          isolateId: 'isolates/1',
          classRefCache: {'HomeBloc': fakeClassRef},
        );

        // Act: retainingPath with a warm cache entry.
        await probe.retainingPath('HomeBloc');

        // Assert: no getAllocationProfile call was made.
        expect(fakeService.allocationProfileCalls, 0);
      },
    );

    test(
      'retainingPath falls back to getAllocationProfile when cache is cold',
      () async {
        final probe = VmHeapProbe();
        final fakeService = _CountingFakeService();

        // Cold cache — no classRefCache entries injected.
        probe.debugInjectServiceAndCache(
          fakeService,
          isolateId: 'isolates/1',
        );

        await probe.retainingPath('HomeBloc');

        // Assert: exactly one getAllocationProfile call was made.
        expect(fakeService.allocationProfileCalls, 1);
      },
    );

    test(
      'cache is populated by capture() so subsequent retainingPath skips getAllocationProfile',
      () async {
        final probe = VmHeapProbe();
        final fakeService = _CountingFakeService();

        probe.debugInjectServiceAndCache(fakeService, isolateId: 'isolates/1');

        // capture() should warm the cache.
        await probe.capture(forceGc: false);

        // Reset call counter AFTER capture.
        fakeService.allocationProfileCalls = 0;

        // Now retainingPath should find the cache warm.
        await probe.retainingPath('HomeBloc');

        expect(fakeService.allocationProfileCalls, 0);
      },
    );
  });
}
