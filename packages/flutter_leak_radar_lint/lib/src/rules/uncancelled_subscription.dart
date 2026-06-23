// lib/src/rules/uncancelled_subscription.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/dispose_analysis.dart';
import '../util/state_class.dart';
import '../util/type_checkers.dart';

/// Flags a [StreamSubscription] stored in a class FIELD (assigned from
/// `.listen()`) that is never cancelled in `dispose()` / `close()`.
///
/// Only FIELD declarations are reported. Local-variable subscriptions
/// (where the result of `.listen()` is discarded or kept in a local) are
/// intentionally out of scope for this rule.
///
/// Severity: WARNING.
/// Tier-B fix: auto-inserts `<field>?.cancel();` into the teardown.
class UncancelledSubscription extends DartLintRule {
  const UncancelledSubscription() : super(code: _code);

  static const _code = LintCode(
    name: 'uncancelled_subscription',
    problemMessage:
        "The StreamSubscription '{0}' is never cancelled in dispose().",
    correctionMessage:
        "Call '{0}?.cancel()' inside dispose() to prevent memory leaks.",
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
          if (!_isStreamSubscription(fieldType)) continue;

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
  List<Fix> getFixes() => [_InsertCancelCall()];
}

bool _isStreamSubscription(DartType? type) {
  if (type == null) return false;
  return kStreamSubscriptionChecker.isAssignableFromType(type);
}

class _InsertCancelCall extends DartFix {
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
