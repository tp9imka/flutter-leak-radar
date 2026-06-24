// test/precise/force_gc_test.dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_leak_radar/src/precise/force_gc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forceGc() advances reachabilityBarrier', () async {
    final barrier = developer.reachabilityBarrier;
    await forceGc(fullGcCycles: 1);
    expect(developer.reachabilityBarrier, greaterThanOrEqualTo(barrier + 1));
  });

  test('forceGc() with timeout that expires throws TimeoutException', () async {
    await expectLater(
      () => forceGc(
        timeout: const Duration(microseconds: 1),
        fullGcCycles: 999999,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
