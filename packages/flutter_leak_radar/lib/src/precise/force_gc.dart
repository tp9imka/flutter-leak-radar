// lib/src/precise/force_gc.dart
import 'dart:async';
import 'dart:developer' as developer;

/// Forces at least [fullGcCycles] full GC cycles.
///
/// Allocates memory aggressively until [reachabilityBarrier] advances.
/// Only effective in debug/profile builds; no-op in release
/// (reachabilityBarrier is always 0 in release so the function returns
/// immediately).
///
/// Use [timeout] to cap the wait. Throws [TimeoutException] if exceeded.
///
/// Gate this call with [kDebugMode] or [kProfileMode] at call sites —
/// calling it in release builds is harmless but pointless.
Future<void> forceGc({Duration? timeout, int fullGcCycles = 1}) async {
  final stopwatch = timeout == null ? null : (Stopwatch()..start());
  final barrier = developer.reachabilityBarrier;
  final storage = <List<int>>[];

  while (developer.reachabilityBarrier < barrier + fullGcCycles) {
    if ((stopwatch?.elapsed ?? Duration.zero) > (timeout ?? Duration.zero)) {
      throw TimeoutException('forceGc timed out', timeout);
    }
    await Future<void>.delayed(Duration.zero);
    storage.add(List.generate(30000, (n) => n));
    if (storage.length > 100) storage.removeAt(0);
  }
}
