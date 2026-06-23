// test/discarded_listen_result_test.dart
import 'dart:io';

import 'package:flutter_leak_radar_lint/src/rules/discarded_listen_result.dart';
import 'package:test/test.dart';

void main() {
  const rule = DiscardedListenResult();

  File fixture(String name) => File(
    '${Directory.current.path}/test/fixtures/discarded_listen_result/$name',
  );

  test('flags a discarded .listen() result', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('bad.dart'));
    expect(
      errors,
      isNotEmpty,
      reason: 'expected at least one discarded_listen_result lint',
    );
    expect(
      errors.every((e) => e.diagnosticCode.name == 'discarded_listen_result'),
      isTrue,
    );
  });

  test('does not flag a .listen() result that is assigned', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
    expect(
      errors,
      isEmpty,
      reason: 'no lint expected when subscription result is captured',
    );
  });
}
