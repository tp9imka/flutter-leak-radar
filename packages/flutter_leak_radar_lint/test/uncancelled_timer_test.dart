// test/uncancelled_timer_test.dart
import 'dart:io';

import 'package:flutter_leak_radar_lint/src/rules/uncancelled_timer.dart';
import 'package:test/test.dart';

void main() {
  const rule = UncancelledTimer();

  File fixture(String name) => File(
        '${Directory.current.path}/test/fixtures/uncancelled_timer/$name',
      );

  test('flags a Timer field not cancelled in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('bad.dart'));
    expect(
      errors,
      isNotEmpty,
      reason: 'expected at least one uncancelled_timer lint',
    );
    expect(
      errors.every((e) => e.diagnosticCode.name == 'uncancelled_timer'),
      isTrue,
    );
  });

  test('does not flag a Timer that is cancelled in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
    expect(
      errors,
      isEmpty,
      reason: 'no lint expected when Timer is cancelled in dispose()',
    );
  });
}
