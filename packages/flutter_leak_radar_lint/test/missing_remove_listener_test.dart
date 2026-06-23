// test/missing_remove_listener_test.dart
import 'dart:io';

import 'package:flutter_leak_radar_lint/src/rules/missing_remove_listener.dart';
import 'package:test/test.dart';

void main() {
  const rule = MissingRemoveListener();

  File fixture(String name) => File(
    '${Directory.current.path}/test/fixtures/missing_remove_listener/$name',
  );

  test('flags addListener tear-off with no matching removeListener', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('bad.dart'));
    expect(
      errors,
      hasLength(2),
      reason:
          'expected two missing_remove_listener lints '
          '(no removeListener, and wrong-callback removeListener)',
    );
    expect(
      errors.every((e) => e.diagnosticCode.name == 'missing_remove_listener'),
      isTrue,
    );
  });

  test(
    'stays silent for paired / closure / controller / out-of-scope',
    () async {
      final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
      expect(
        errors,
        isEmpty,
        reason:
            'no lint expected when removeListener pairs, callback is a closure, '
            'receiver is a disposable controller, or class has no teardown',
      );
    },
  );
}
