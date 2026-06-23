// test/undisposed_controller_test.dart
import 'dart:io';

import 'package:flutter_leak_radar_lint/src/rules/undisposed_controller.dart';
import 'package:test/test.dart';

void main() {
  const rule = UndisposedController();

  // Resolve fixtures using a path relative to this source file.
  // `String.fromEnvironment` approach is fragile; instead we use
  // Directory.current which inside `dart test` is the package root.
  File fixture(String name) => File(
        '${Directory.current.path}/test/fixtures/undisposed_controller/$name',
      );

  test('flags an undisposed TextEditingController field', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('bad.dart'));
    expect(
      errors,
      isNotEmpty,
      reason: 'expected at least one undisposed_controller lint',
    );
    expect(
      errors.every((e) => e.diagnosticCode.name == 'undisposed_controller'),
      isTrue,
    );
  });

  test('does not flag a controller that is disposed in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
    expect(
      errors,
      isEmpty,
      reason: 'no lint expected for a properly disposed controller',
    );
  });
}
