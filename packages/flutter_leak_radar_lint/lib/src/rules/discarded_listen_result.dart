// lib/src/rules/discarded_listen_result.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/type_checkers.dart';

/// Flags a [MethodInvocation] named `listen` on a [Stream] receiver
/// whose [StreamSubscription] return value is discarded — i.e. the call
/// appears as a bare [ExpressionStatement] without being assigned or awaited.
///
/// This is a Tier C (message-only) rule: the correct fix requires capturing
/// the subscription in a named field and cancelling it in dispose()/close(),
/// which involves naming and placement decisions that an automated edit cannot
/// make safely.
///
/// False-positive cases (these are NOT flagged):
/// - `.listen(...)` result assigned to a local variable.
/// - `.listen(...)` result assigned to a field.
/// - `.listen(...)` returned from a function.
/// - The canonical `// ignore: discarded_listen_result` suppression for
///   intentionally app-lifetime subscriptions on a global stream.
class DiscardedListenResult extends DartLintRule {
  const DiscardedListenResult() : super(code: _code);

  static const _code = LintCode(
    name: 'discarded_listen_result',
    problemMessage:
        "The StreamSubscription returned by '.listen()' is discarded and can never be cancelled.",
    correctionMessage:
        "Assign the subscription to a field and cancel it in dispose() or close().",
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addExpressionStatement((node) {
      final expr = node.expression;
      if (expr is! MethodInvocation) return;
      if (expr.methodName.name != 'listen') return;

      // Check receiver is assignable to Stream.
      final target = expr.target;
      if (target == null) return;
      final targetType = target.staticType;
      if (targetType == null) return;
      if (!kStreamChecker.isAssignableFromType(targetType)) return;

      // The result is being discarded (it's a bare ExpressionStatement).
      reporter.atNode(expr.methodName, _code);
    });
  }

  // Tier C: no auto-fix.
  @override
  List<Fix> getFixes() => [];
}
