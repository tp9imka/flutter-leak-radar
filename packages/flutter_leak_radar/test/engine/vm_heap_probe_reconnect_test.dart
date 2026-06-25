// test/engine/vm_heap_probe_reconnect_test.dart
//
// Task 1.4 — verify reconnect-latch recovery in VmHeapProbe.
// Confirms that:
//   (a) a transient socket failure does NOT permanently brick the probe.
//   (b) the probe retries on the next capture() after the backoff window.
//   (c) _classRefCache is cleared when a socket failure is detected mid-capture.
//   (d) a stale classRef id is NOT reused after reconnect (cache cleared).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';
import 'package:vm_service/vm_service.dart';

// ---------------------------------------------------------------------------
// Fake VM service — returns one allocation-profile member.
// ---------------------------------------------------------------------------

final _fakeClassRef = ClassRef(id: 'classes/42', name: 'Dummy');

class _FakeService extends Fake implements VmService {
  int profileCalls = 0;

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) async {
    profileCalls++;
    final member = ClassHeapStats()
      ..classRef = _fakeClassRef
      ..instancesCurrent = 2
      ..bytesCurrent = 128;
    return AllocationProfile()..members = [member];
  }

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('VmHeapProbe reconnect-latch recovery', () {
    test(
      'probe recovers after transient socket failure on next capture',
      () async {
        final fakeService = _FakeService();
        var callCount = 0;
        final probe = VmHeapProbe();

        // First connection attempt: fail; second: succeed.
        probe.debugInjectConnectionFactory(() async {
          callCount++;
          if (callCount == 1) throw const SocketException('transient');
          return fakeService;
        });

        // First capture: connection fails → empty snapshot (graceful).
        final snap1 = await probe.capture(forceGc: false);
        expect(
          snap1.samples,
          isEmpty,
          reason: 'first capture must degrade gracefully on connect failure',
        );

        // Override retry window so we don't wait 30 s in tests.
        probe.debugOverrideNextRetryAllowedAt(
          DateTime.now().subtract(const Duration(seconds: 1)),
        );

        // Second capture: connection succeeds → real data.
        final snap2 = await probe.capture(forceGc: false);
        expect(
          snap2.samples,
          isNotEmpty,
          reason: 'probe must recover on next capture after transient error',
        );
      },
    );

    test('_classRefCache is cleared when socket drops mid-capture', () async {
      final fakeService = _FakeService();
      final staleClassRef = ClassRef(id: 'classes/STALE', name: 'Dummy');
      final probe = VmHeapProbe();

      // Inject a connected state with a stale cache entry.
      probe.debugInjectServiceAndCache(
        fakeService,
        isolateId: 'isolates/1',
        classRefCache: {'Dummy': staleClassRef},
      );

      // Verify cache is warm before the drop.
      expect(probe.debugClassRefCache['Dummy']?.id, 'classes/STALE');

      // Simulate a socket drop during capture by making getAllocationProfile throw.
      final droppingService = _DroppingService();
      probe.debugInjectServiceAndCache(
        droppingService,
        isolateId: 'isolates/1',
      );

      final snap = await probe.capture(forceGc: false);
      expect(
        snap.samples,
        isEmpty,
        reason: 'capture must return empty on socket drop',
      );

      // Cache must be cleared after the drop.
      expect(
        probe.debugClassRefCache,
        isEmpty,
        reason: 'stale cache entries must be cleared after socket drop',
      );
    });

    test('stale classRef id is not reused after reconnect', () async {
      // Phase 1: connect with service A, warm the cache with stale id.
      final serviceA = _FakeService();
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        serviceA,
        isolateId: 'isolates/1',
        classRefCache: {'Dummy': ClassRef(id: 'classes/OLD', name: 'Dummy')},
      );

      // Phase 2: socket drops mid-capture → cache cleared, service nulled.
      final droppingService = _DroppingService();
      probe.debugInjectServiceAndCache(
        droppingService,
        isolateId: 'isolates/1',
      );
      await probe.capture(forceGc: false); // triggers drop

      // Phase 3: reconnect with fresh service that returns new ids.
      final serviceB = _FakeService(); // _fakeClassRef has id 'classes/42'
      probe.debugInjectConnectionFactory(() async => serviceB);
      probe.debugOverrideNextRetryAllowedAt(
        DateTime.now().subtract(const Duration(seconds: 1)),
      );

      // Capture repopulates cache with fresh ids.
      final snap = await probe.capture(forceGc: false);
      expect(snap.samples, isNotEmpty);

      // The cache now holds the NEW id, not the stale one.
      expect(
        probe.debugClassRefCache['Dummy']?.id,
        'classes/42',
        reason: 'cache must be repopulated with fresh ids after reconnect',
      );
      expect(probe.debugClassRefCache['Dummy']?.id, isNot('classes/OLD'));
    });

    test(
      'isConnected tracks state; reconnect bypasses the backoff window',
      () async {
        final fakeService = _FakeService();
        var callCount = 0;
        final probe = VmHeapProbe();
        probe.debugInjectConnectionFactory(() async {
          callCount++;
          if (callCount == 1) throw const SocketException('transient');
          return fakeService;
        });

        expect(
          probe.isConnected,
          isFalse,
          reason: 'offline before any connect',
        );

        // First capture fails to connect and arms the 30s backoff.
        await probe.capture(forceGc: false);
        expect(probe.isConnected, isFalse);

        // Manual reconnect ignores the backoff and connects on the 2nd attempt.
        final ok = await probe.reconnect();
        expect(ok, isTrue, reason: 'reconnect should connect past the backoff');
        expect(probe.isConnected, isTrue);
      },
    );

    test(
      'permanent failure does not retry immediately (backoff respected)',
      () async {
        var callCount = 0;
        final probe = VmHeapProbe();

        // Every connection attempt fails.
        probe.debugInjectConnectionFactory(() async {
          callCount++;
          throw const SocketException('always fails');
        });

        await probe.capture(forceGc: false); // first attempt, call #1
        await probe.capture(forceGc: false); // within backoff → no retry

        expect(
          callCount,
          1,
          reason: 'must not retry within the backoff window',
        );
      },
    );
  });
}

/// A VmService that throws a SocketException on getAllocationProfile, simulating
/// a mid-capture socket drop.
class _DroppingService extends Fake implements VmService {
  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) async {
    throw const SocketException('connection reset');
  }

  @override
  Future<void> dispose() async {}
}
