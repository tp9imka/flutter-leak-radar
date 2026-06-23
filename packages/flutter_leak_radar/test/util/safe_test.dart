// test/util/safe_test.dart
import 'package:flutter_leak_radar/src/util/safe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runSafely returns body result on success', () {
    expect(runSafely<int>(() => 42, fallback: -1), 42);
  });

  test('runSafely returns fallback and never throws on error', () {
    expect(runSafely<int>(() => throw StateError('boom'), fallback: -1), -1);
  });

  test('runSafelyAsync returns fallback on async error', () async {
    final value = await runSafelyAsync<int>(
      () async => throw Exception('boom'),
      fallback: 7,
    );
    expect(value, 7);
  });
}
