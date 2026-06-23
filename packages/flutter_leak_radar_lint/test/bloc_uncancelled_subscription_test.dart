// test/bloc_uncancelled_subscription_test.dart
import 'dart:io';

import 'package:flutter_leak_radar_lint/src/rules/bloc_uncancelled_subscription.dart';
import 'package:test/test.dart';

void main() {
  const rule = BlocUncancelledSubscription();

  File fixture(String name) => File(
    '${Directory.current.path}/test/fixtures/bloc_uncancelled_subscription/$name',
  );

  test('flags constructor .listen() not cancelled in close()', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('bad.dart'));
    expect(
      errors,
      hasLength(3),
      reason:
          'expected three bloc_uncancelled_subscription lints '
          '(discarded, field-no-close, field-close-no-cancel)',
    );
    expect(
      errors.every(
        (e) => e.diagnosticCode.name == 'bloc_uncancelled_subscription',
      ),
      isTrue,
    );
  });

  test('does not flag cancelled / emit.forEach / out-of-scope cases', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
    expect(
      errors,
      isEmpty,
      reason:
          'no lint expected when cancelled in close(), via emit.forEach/onEach, '
          'in a non-constructor method, or in a non-bloc class',
    );
  });
}
