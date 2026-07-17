import 'package:radar_ci/radar_ci.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../support/fake_vm_service.dart';

/// Virtual clock: [delay] advances now instantly so retry/stability windows
/// run without real waiting, and the deadline is evaluated deterministically.
final class _FakeClock implements RunClock {
  int _now = 0;

  @override
  int nowMicros() => _now;

  @override
  Future<void> delay(Duration duration) async {
    if (duration > Duration.zero) _now += duration.inMicroseconds;
  }
}

/// A fake service whose `getVM` (the default probe) runs [_onProbe] each call,
/// so a test can script a connection that answers, then drops, then answers.
final class _ProbeService extends FakeVmService {
  _ProbeService(this._onProbe);

  final Future<void> Function() _onProbe;
  int probeCalls = 0;
  bool disposed = false;

  @override
  Future<VM> getVM() async {
    probeCalls++;
    await _onProbe();
    return VM(isolates: const []);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// A probe behaviour that succeeds for the first [okCount] calls, then throws
/// the vm_service disposal error on every call after — a connection that
/// connects, answers a beat, then is torn down.
Future<void> Function() _dropsAfter(int okCount) {
  var calls = 0;
  return () async {
    calls++;
    if (calls > okCount) {
      throw RPCError('getVM', -32000, 'Service connection disposed');
    }
  };
}

void main() {
  group('connectStableVmService', () {
    test('rides out a refused connect and returns once it succeeds', () async {
      final stable = _ProbeService(() async {});
      var attempts = 0;
      final retries = <String>[];

      final service = await connectStableVmService(
        'ws://127.0.0.1:1/ws',
        clock: _FakeClock(),
        onRetry: retries.add,
        connect: (_) async {
          attempts++;
          if (attempts < 3) {
            throw const SocketExceptionLike('Connection refused');
          }
          return stable;
        },
      );

      expect(service, same(stable));
      expect(attempts, 3, reason: 'two refusals then success');
      expect(retries, hasLength(2), reason: 'each refusal warns once');
      expect(stable.disposed, isFalse);
    });

    test('reconnects when the connection drops inside the stability '
        'window, disposing the doomed one', () async {
      final doomed = _ProbeService(_dropsAfter(1));
      final stable = _ProbeService(() async {});
      final connected = <_ProbeService>[];

      final service = await connectStableVmService(
        'ws://127.0.0.1:1/ws',
        clock: _FakeClock(),
        connect: (_) async {
          final next = connected.isEmpty ? doomed : stable;
          connected.add(next);
          return next;
        },
      );

      expect(service, same(stable), reason: 'the durable connection wins');
      expect(doomed.disposed, isTrue, reason: 'the dropped one is disposed');
      expect(
        doomed.probeCalls,
        greaterThanOrEqualTo(2),
        reason: 'the drop is only visible on a re-probe, not the first',
      );
      expect(stable.disposed, isFalse);
    });

    test('probes across the whole window before trusting a connection', () async {
      // Stable across the default 2 s window at 500 ms cadence: probe at 0 then
      // one per interval — at least 3, never just the single connect-time RPC.
      final stable = _ProbeService(() async {});

      await connectStableVmService(
        'ws://127.0.0.1:1/ws',
        clock: _FakeClock(),
        connect: (_) async => stable,
      );

      expect(stable.probeCalls, greaterThan(1));
    });

    test('throws an honest VmConnectException when no stable connection is '
        'reached within the budget', () async {
      final attempted = <_ProbeService>[];

      await expectLater(
        connectStableVmService(
          'ws://127.0.0.1:1/ws',
          clock: _FakeClock(),
          timeout: const Duration(seconds: 5),
          connect: (_) async {
            final service = _ProbeService(_dropsAfter(0));
            attempted.add(service);
            return service;
          },
        ),
        throwsA(isA<VmConnectException>()),
      );

      expect(attempted, isNotEmpty);
      expect(
        attempted.every((s) => s.disposed),
        isTrue,
        reason: 'every failed attempt is disposed, none leaked',
      );
    });
  });
}

/// A stand-in error for a refused socket connect (kept dart:io-free here).
final class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'SocketExceptionLike: $message';
}
