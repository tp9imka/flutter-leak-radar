// test/uncancelled_subscription_test.dart
import 'dart:io';

import 'package:flutter_leak_radar_lint/src/rules/uncancelled_subscription.dart';
import 'package:test/test.dart';

void main() {
  const rule = UncancelledSubscription();

  File fixture(String name) => File(
        '${Directory.current.path}/test/fixtures/uncancelled_subscription/$name',
      );

  test('flags a StreamSubscription field not cancelled in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('bad.dart'));
    expect(
      errors,
      isNotEmpty,
      reason: 'expected at least one uncancelled_subscription lint',
    );
    expect(
      errors.every((e) => e.diagnosticCode.name == 'uncancelled_subscription'),
      isTrue,
    );
  });

  test('does not flag a subscription cancelled in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
    expect(
      errors,
      isEmpty,
      reason: 'no lint expected when subscription is cancelled in dispose()',
    );
  });

  test(
    'flags a StreamSubscription field not cancelled in close() (BlocBase)',
    () async {
      final errors = await rule.testAnalyzeAndRun(fixture('bad_close.dart'));
      expect(
        errors,
        isNotEmpty,
        reason: 'expected uncancelled_subscription lint for BlocBase.close()',
      );
      expect(
        errors.every((e) => e.diagnosticCode.name == 'uncancelled_subscription'),
        isTrue,
      );
    },
  );
}
