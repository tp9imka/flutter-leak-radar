// lib/src/rules/undisposed_controller.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/dispose_analysis.dart';
import '../util/state_class.dart';
import '../util/type_checkers.dart';

/// Flags a [State<T>] subclass field whose type is a known disposable
/// Flutter controller (AnimationController, TextEditingController, etc.)
/// when that field has no corresponding `<field>.dispose()` call inside
/// the class's `dispose()` override.
///
/// Severity: WARNING — this is a statically-visible leak shape.
///
/// False-positive suppressions:
/// - `late` field with no initializer AND not assigned in `initState()` (not proven owned).
/// - Field assigned from a constructor parameter (not created here).
/// - Field disposed inside any nested block (if/try/for) inside dispose().
class UndisposedController extends DartLintRule {
  const UndisposedController() : super(code: _code);

  static const _code = LintCode(
    name: 'undisposed_controller',
    problemMessage:
        "The controller '{0}' is created in this State but is never disposed in dispose().",
    correctionMessage:
        "Override dispose() and call '{0}.dispose()' before super.dispose().",
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addClassDeclaration((cls) {
      if (!isStateSubclass(cls)) return;

      final teardown = findTeardownMethod(cls, 'dispose');

      for (final member in cls.members) {
        if (member is! FieldDeclaration || member.isStatic) continue;

        for (final variable in member.fields.variables) {
          final fieldName = variable.name.lexeme;

          // Prefer the explicit type annotation; fall back to the inferred
          // type from the variable's declared element (handles `final _c = Foo()`
          // where there is no explicit type node).
          final fieldType = member.fields.type?.type ??
              variable.declaredFragment?.element.type;
          if (!_isDisposableController(fieldType)) continue;

          // Heuristic: skip `late` fields with no initializer — not proven owned
          // unless they are assigned in initState().
          if (variable.initializer == null &&
              member.fields.isLate &&
              !_isAssignedInInitState(cls, fieldName)) {
            continue;
          }

          // Heuristic: skip fields assigned from a constructor parameter.
          if (isConstructorParam(cls, fieldName)) continue;

          if (teardown == null ||
              !disposedInTeardown(
                teardownMethod: teardown,
                receiverName: fieldName,
                teardownCall: 'dispose',
              )) {
            reporter.atToken(
              variable.name,
              _code,
              arguments: [fieldName],
            );
          }
        }
      }
    });
  }

  @override
  List<Fix> getFixes() => [_AddDisposeCall()];
}

bool _isDisposableController(DartType? type) {
  if (type == null) return false;
  return kControllerTypes.any((checker) => checker.isAssignableFromType(type));
}

/// Checks whether [fieldName] is assigned anywhere inside `initState()`.
bool _isAssignedInInitState(ClassDeclaration cls, String fieldName) {
  for (final member in cls.members) {
    if (member is! MethodDeclaration) continue;
    if (member.name.lexeme != 'initState') continue;
    final body = member.body;
    if (body is! BlockFunctionBody) continue;
    for (final stmt in body.block.statements) {
      if (stmt is ExpressionStatement) {
        final expr = stmt.expression;
        if (expr is AssignmentExpression) {
          final lhs = expr.leftHandSide;
          if (lhs is SimpleIdentifier && lhs.name == fieldName) return true;
          if (lhs is PrefixedIdentifier &&
              lhs.identifier.name == fieldName) {
            return true;
          }
        }
      }
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tier A quick-fix: insert <field>.dispose() into dispose().
// ---------------------------------------------------------------------------

class _AddDisposeCall extends DartFix {
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
      if (!isStateSubclass(cls)) return;

      // Re-derive field name by checking which field token overlaps the error range.
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

      final existingDispose = findTeardownMethod(cls, 'dispose');

      final changeBuilder = reporter.createChangeBuilder(
        message: "Add '$fieldName.dispose()' to dispose()",
        priority: 80,
      );

      if (existingDispose != null) {
        // Insert before super.dispose() if present, else at end of block.
        changeBuilder.addDartFileEdit((builder) {
          final body = existingDispose.body;
          if (body is! BlockFunctionBody) return;

          // Find super.dispose() call offset.
          int insertOffset = body.block.rightBracket.offset;
          for (final stmt in body.block.statements) {
            if (stmt is ExpressionStatement) {
              final expr = stmt.expression;
              if (expr is MethodInvocation &&
                  expr.target is SuperExpression &&
                  expr.methodName.name == 'dispose') {
                insertOffset = stmt.offset;
                break;
              }
            }
          }
          builder.addSimpleInsertion(insertOffset, '    $fieldName.dispose();\n');
        });
      } else {
        // Synthesize the entire dispose() override.
        changeBuilder.addDartFileEdit((builder) {
          final insertAt = cls.rightBracket.offset;
          builder.addSimpleInsertion(insertAt, '''

  @override
  void dispose() {
    $fieldName.dispose();
    super.dispose();
  }
''');
        });
      }
    });
  }
}
