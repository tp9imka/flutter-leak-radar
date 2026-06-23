// lib/src/rules/bloc_uncancelled_subscription.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/dispose_analysis.dart';
import '../util/state_class.dart';
import '../util/type_checkers.dart';

/// Flags a `package:bloc` [BlocBase] subclass (Bloc / Cubit) that subscribes to
/// a stream via `.listen(...)` in its CONSTRUCTOR without cancelling the
/// subscription in the overridden `close()`.
///
/// Two shapes are flagged:
/// - `stream.listen(...)` whose result is DISCARDED (a bare statement) — there
///   is no subscription object to cancel, so the subscription lives for the
///   life of the bloc.
/// - `_field = stream.listen(...)` assigned to a class field that is never
///   `.cancel()`-ed in `close()`.
///
/// The rule is ONLY active when the consumer depends on `package:bloc`: the
/// gate is [isBlocBaseSubclass], which resolves against the bloc `BlocBase`
/// type. If `package:bloc` is not resolvable, no class matches and the rule is
/// silent.
///
/// `emit.forEach(...)` / `emit.onEach(...)` are bloc-managed lifecycle helpers
/// and are NOT subscriptions the author owns — they are never flagged (they are
/// not `.listen` calls, and any `.listen` whose receiver is `emit` is skipped
/// defensively).
///
/// Scope guard (FP-safety): only `.listen` calls TEXTUALLY INSIDE THE
/// CONSTRUCTOR are considered. `.listen` started from a regular method is out of
/// scope here (and a field case is already covered by `uncancelled_subscription`
/// for BlocBase), which keeps this rule from double-reporting.
///
/// Severity: WARNING. Field case has a partial fix conceptually; here it is
/// message-only to keep the discarded and field shapes uniform and FP-safe.
class BlocUncancelledSubscription extends DartLintRule {
  const BlocUncancelledSubscription() : super(code: _code);

  static const _code = LintCode(
    name: 'bloc_uncancelled_subscription',
    problemMessage:
        "This .listen() subscription created in the bloc constructor is never cancelled in close().",
    correctionMessage:
        "Assign the subscription to a field and call '<field>.cancel()' in the overridden close().",
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addClassDeclaration((cls) {
      // Gate: bloc-only. Resolves against package:bloc's BlocBase.
      if (!isBlocBaseSubclass(cls)) return;

      final closeMethod = findTeardownMethod(cls, 'close');

      // Collect class field names so we can recognise `_field = x.listen(...)`.
      final fieldNames = <String>{};
      for (final member in cls.members) {
        if (member is FieldDeclaration && !member.isStatic) {
          for (final v in member.fields.variables) {
            fieldNames.add(v.name.lexeme);
          }
        }
      }

      for (final member in cls.members) {
        if (member is! ConstructorDeclaration) continue;
        final body = member.body;

        final visitor = _ConstructorListenVisitor(fieldNames);
        body.accept(visitor);

        for (final found in visitor.calls) {
          switch (found.kind) {
            case _ListenKind.discarded:
              // Bare statement: nothing to cancel — always a leak.
              reporter.atNode(found.invocation.methodName, _code);
            case _ListenKind.assignedToField:
              // Clear the flag only if cancelled in close().
              final cancelled =
                  closeMethod != null &&
                  disposedInTeardown(
                    teardownMethod: closeMethod,
                    receiverName: found.field!,
                    teardownCall: 'cancel',
                  );
              if (!cancelled) {
                reporter.atNode(found.invocation.methodName, _code);
              }
            case _ListenKind.other:
              // Local var / return / await / argument: out of scope, skip
              // (conservative — avoid false positives).
              break;
          }
        }
      }
    });
  }

  // Message-only: keeping discarded + field shapes uniform and FP-safe.
  @override
  List<Fix> getFixes() => [];
}

enum _ListenKind { discarded, assignedToField, other }

/// A `.listen(...)` invocation found inside a constructor body.
class _ListenFinding {
  _ListenFinding(this.invocation, this.kind, this.field);

  final MethodInvocation invocation;
  final _ListenKind kind;

  /// The class-field name the subscription is assigned to, for
  /// [_ListenKind.assignedToField]; otherwise `null`.
  final String? field;
}

class _ConstructorListenVisitor extends RecursiveAstVisitor<void> {
  _ConstructorListenVisitor(this._fieldNames);

  final Set<String> _fieldNames;
  final List<_ListenFinding> calls = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'listen') {
      final target = node.target;
      final targetType = target?.staticType;
      final isStream =
          targetType != null && kStreamChecker.isAssignableFromType(targetType);

      // Defensive skip: emit.* helpers are not `.listen`, but never treat a
      // subscription whose receiver is `emit` as author-owned.
      final receiverIsEmit =
          target is SimpleIdentifier && target.name == 'emit';

      if (isStream && !receiverIsEmit) {
        calls.add(_classify(node));
      }
    }
    super.visitMethodInvocation(node);
  }

  /// Classifies the `.listen(...)` result by how it is consumed:
  /// - assigned to a KNOWN FIELD     → [_ListenKind.assignedToField]
  /// - bare `ExpressionStatement`    → [_ListenKind.discarded]
  /// - anything else (local var,
  ///   return, await, argument)      → [_ListenKind.other] (conservatively
  ///                                    ignored to avoid false positives)
  _ListenFinding _classify(MethodInvocation node) {
    final parent = node.parent;

    // `_field = x.listen(...)`
    if (parent is AssignmentExpression && parent.rightHandSide == node) {
      final lhs = parent.leftHandSide;
      String? fieldName;
      if (lhs is SimpleIdentifier && _fieldNames.contains(lhs.name)) {
        fieldName = lhs.name;
      } else if (lhs is PrefixedIdentifier &&
          lhs.prefix.name == 'this' &&
          _fieldNames.contains(lhs.identifier.name)) {
        fieldName = lhs.identifier.name;
      }
      if (fieldName != null) {
        return _ListenFinding(node, _ListenKind.assignedToField, fieldName);
      }
      // Assignment to a non-field (e.g. a local) — out of scope.
      return _ListenFinding(node, _ListenKind.other, null);
    }

    // Bare `x.listen(...);` as a statement → discarded.
    if (parent is ExpressionStatement) {
      return _ListenFinding(node, _ListenKind.discarded, null);
    }

    // Local var, return, await, argument, etc. — conservatively ignored.
    return _ListenFinding(node, _ListenKind.other, null);
  }
}
