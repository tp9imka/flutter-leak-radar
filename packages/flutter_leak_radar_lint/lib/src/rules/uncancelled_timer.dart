// lib/src/rules/uncancelled_timer.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/dispose_analysis.dart';
import '../util/state_class.dart';
import '../util/type_checkers.dart';

/// Flags a [Timer] stored in a class FIELD that is never cancelled in
/// `dispose()` / `close()`.
///
/// Only FIELD declarations are reported. Local-variable timers (fire-and-forget
/// or stored in a local) are intentionally out of scope — those are not heap-
/// pinned by the widget tree and are not a widget-lifecycle leak.
///
/// Constructor-injected fields are excluded: the Timer is externally owned and
/// the State must not cancel it.
///
/// Severity: WARNING.
/// Tier-B fix: auto-inserts `<field>?.cancel();` into the teardown.
class UncancelledTimer extends DartLintRule {
  const UncancelledTimer() : super(code: _code);

  static const _code = LintCode(
    name: 'uncancelled_timer',
    problemMessage:
        "The Timer '{0}' is stored in a field but is never cancelled in dispose().",
    correctionMessage:
        "Call '{0}?.cancel()' inside dispose() to prevent the timer from "
        "running after the widget is disposed.",
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
          final fieldType = member.fields.type?.type ??
              variable.declaredFragment?.element.type;
          if (!_isTimer(fieldType)) continue;

          // Skip fields that are externally owned (passed in via constructor).
          if (isConstructorParam(cls, fieldName)) continue;

          if (teardown == null ||
              !disposedInTeardown(
                teardownMethod: teardown,
                receiverName: fieldName,
                teardownCall: 'cancel',
              )) {
            reporter.atToken(variable.name, _code, arguments: [fieldName]);
          }
        }
      }
    });
  }

  @override
  List<Fix> getFixes() => [_InsertTimerCancelCall()];
}

bool _isTimer(DartType? type) {
  if (type == null) return false;
  return kTimerChecker.isAssignableFromType(type);
}

class _InsertTimerCancelCall extends DartFix {
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
        message: "Add '$fieldName?.cancel()' to $teardownName()",
        priority: 75,
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
          builder.addSimpleInsertion(insertOffset, '    $fieldName?.cancel();\n');
        });
      } else {
        changeBuilder.addDartFileEdit((builder) {
          final insertAt = cls.rightBracket.offset;
          final superCall = teardownName == 'close'
              ? '    return super.close();\n'
              : '    super.$teardownName();\n';
          builder.addSimpleInsertion(insertAt, '''

  @override
  ${teardownName == 'close' ? 'Future<void>' : 'void'} $teardownName() {
    $fieldName?.cancel();
    $superCall}
''');
        });
      }
    });
  }
}
