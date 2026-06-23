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

  test(
    'flags an inferred-type controller field (no explicit type annotation)',
    () async {
      final errors = await rule.testAnalyzeAndRun(fixture('bad.dart'));
      final inferredTypeErrors = errors
          .where((e) => e.diagnosticCode.name == 'undisposed_controller')
          .toList();
      // _InferredTypeBadState uses `final _c = TextEditingController()` with no
      // explicit type annotation — the rule must resolve the type from the
      // initializer's static type (via declaredFragment?.element.type).
      expect(
        inferredTypeErrors.any((e) => e.message.contains("'_c'")),
        isTrue,
        reason: 'inferred-type field _c should be flagged',
      );
    },
  );

  test('does not flag a controller that is disposed in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
    expect(
      errors,
      isEmpty,
      reason: 'no lint expected for a properly disposed controller',
    );
  });

  test(
    'does not flag a controller injected via field formal parameter (this._controller)',
    () async {
      // _GoodFieldFormalParamState takes `this._controller` in its constructor.
      // The controller is externally owned — the State must NOT flag it even
      // though there is no dispose() override.
      final errors = await rule.testAnalyzeAndRun(fixture('good.dart'));
      expect(
        errors,
        isEmpty,
        reason:
            'constructor-injected controller via FieldFormalParameter must not be flagged',
      );
    },
  );
}
