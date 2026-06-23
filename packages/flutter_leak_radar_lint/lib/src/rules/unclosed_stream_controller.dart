// lib/src/rules/unclosed_stream_controller.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/dispose_analysis.dart';
import '../util/state_class.dart';
import '../util/type_checkers.dart';

/// Flags a [StreamController] stored in a class FIELD that is never closed in
/// the teardown method (`dispose()` for [State] subclasses, `close()` for
/// `bloc` [BlocBase] subclasses).
///
/// Only FIELD declarations are reported. Local-variable controllers are out of
/// scope — they are not pinned by the widget tree and are not a lifecycle leak.
///
/// Mirrors [UncancelledSubscription] exactly, with `teardownCall: 'close'`.
///
/// Severity: WARNING.
/// Tier-A fix (sync teardown only): auto-inserts `<field>.close();` into the
/// teardown, synthesising a `dispose()` override if absent. A `close()`
/// override is never synthesised (its async return type makes a trivial
/// synthesis incorrect — see [UncancelledSubscription]).
///
/// False-positive suppressions:
/// - Field assigned from a constructor parameter (externally owned).
/// - Controller closed inside any nested block (if/try/for) of teardown.
/// - Class with no recognised teardown method (plain Dart classes).
class UnclosedStreamController extends DartLintRule {
  const UnclosedStreamController() : super(code: _code);

  static const _code = LintCode(
    name: 'unclosed_stream_controller',
    problemMessage:
        "The StreamController '{0}' is created in this class but is never closed in the teardown method.",
    correctionMessage:
        "Call '{0}.close()' inside dispose()/close() to release the controller and its buffer.",
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addClassDeclaration((cls) {
      final teardownName = teardownMethodName(cls);
      if (teardownName == null) return;

      final teardown = findTeardownMethod(cls, teardownName);

      for (final member in cls.members) {
        if (member is! FieldDeclaration || member.isStatic) continue;

        for (final variable in member.fields.variables) {
          final fieldName = variable.name.lexeme;

          // Resolve type per-variable: prefer the explicit annotation, fall back
          // to the inferred type from the variable's declared element.
          final fieldType =
              member.fields.type?.type ??
              variable.declaredFragment?.element.type;
          if (!_isStreamController(fieldType)) continue;

          // Skip fields that are externally owned (passed in via constructor).
          if (isConstructorParam(cls, fieldName)) continue;

          if (teardown == null ||
              !disposedInTeardown(
                teardownMethod: teardown,
                receiverName: fieldName,
                teardownCall: 'close',
              )) {
            reporter.atToken(variable.name, _code, arguments: [fieldName]);
          }
        }
      }
    });
  }

  @override
  List<Fix> getFixes() => [_InsertCloseCall()];
}

bool _isStreamController(DartType? type) {
  if (type == null) return false;
  return kStreamControllerChecker.isAssignableFromType(type);
}

class _InsertCloseCall extends DartFix {
  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError analysisError,
    List<AnalysisError> others,
  ) {
    context.registry.addClassDeclaration((cls) {
      if (!cls.sourceRange.intersects(analysisError.sourceRange)) return;

      final teardownName = teardownMethodName(cls);
      if (teardownName == null) return;

      String? fieldName;
      for (final member in cls.members) {
        if (member is! FieldDeclaration || member.isStatic) continue;
        for (final variable in member.fields.variables) {
          if (variable.name.offset == analysisError.offset) {
            fieldName = variable.name.lexeme;
            break;
          }
        }
        if (fieldName != null) break;
      }
      if (fieldName == null) return;

      final existingTeardown = findTeardownMethod(cls, teardownName);
      final changeBuilder = reporter.createChangeBuilder(
        message: "Add '$fieldName.close()' to $teardownName()",
        priority: 80,
      );

      if (existingTeardown != null) {
        changeBuilder.addDartFileEdit((builder) {
          final body = existingTeardown.body;
          if (body is! BlockFunctionBody) return;

          int insertOffset = body.block.rightBracket.offset;
          for (final stmt in body.block.statements) {
            if (stmt is ExpressionStatement) {
              final expr = stmt.expression;
              if (expr is MethodInvocation &&
                  expr.target is SuperExpression &&
                  expr.methodName.name == teardownName) {
                insertOffset = stmt.offset;
                break;
              }
            }
          }
          builder.addSimpleInsertion(insertOffset, '    $fieldName.close();\n');
        });
      } else if (teardownName != 'close') {
        // Do NOT synthesise a close() override: the async return type makes a
        // trivial synthesis incorrect (needs `await super.close()`). Only
        // synthesise dispose() and other sync teardowns.
        changeBuilder.addDartFileEdit((builder) {
          final insertAt = cls.rightBracket.offset;
          builder.addSimpleInsertion(insertAt, '''

  @override
  void $teardownName() {
    $fieldName.close();
    super.$teardownName();
  }
''');
        });
      }
    });
  }
}
