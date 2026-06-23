// test/unclosed_stream_controller_test.dart
import 'dart:io';

import 'package:flutter_leak_radar_lint/src/rules/unclosed_stream_controller.dart';
import 'package:test/test.dart';

void main() {
  const rule = UnclosedStreamController();

  File fixture(String name) => File(
    '${Directory.current.path}/test/fixtures/unclosed_stream_controller/$name',
  );

  test('flags a StreamController field not closed in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('bad.dart'));
    expect(
      errors,
      hasLength(2),
      reason: 'expected exactly two unclosed_stream_controller lints',
    );
    expect(
      errors.every(
        (e) => e.diagnosticCode.name == 'unclosed_stream_controller',
      ),
      isTrue,
    );
  });

  test('does not flag a StreamController closed/owned correctly', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
    expect(
      errors,
      isEmpty,
      reason: 'no lint expected when controller is closed/local/injected',
    );
  });

  test(
    'flags a StreamController field not closed in close() (BlocBase)',
    () async {
      final errors = await rule.testAnalyzeAndRun(fixture('bad_close.dart'));
      expect(
        errors,
        hasLength(1),
        reason: 'expected unclosed_stream_controller lint for BlocBase.close()',
      );
      expect(
        errors.every(
          (e) => e.diagnosticCode.name == 'unclosed_stream_controller',
        ),
        isTrue,
      );
    },
  );
}
