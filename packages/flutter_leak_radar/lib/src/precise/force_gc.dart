// lib/src/precise/force_gc.dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Forces at least [fullGcCycles] full GC cycles.
///
/// Allocates memory aggressively until [reachabilityBarrier] advances.
/// Only meaningful in debug/profile builds — returns immediately in release
/// mode because [reachabilityBarrier] is always 0 there and the loop would
/// never terminate without a guard.
///
/// Use [timeout] to cap the wait. Throws [TimeoutException] if exceeded.
///
/// This is a test utility. Gate call sites with [kDebugMode] or
/// [kProfileMode] when used outside of tests.
Future<void> forceGc({Duration? timeout, int fullGcCycles = 1}) async {
  // reachabilityBarrier is always 0 in release builds; the loop below
  // would never terminate, so return early.
  if (kReleaseMode) return;

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
