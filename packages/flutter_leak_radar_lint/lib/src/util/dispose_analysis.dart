// lib/src/util/dispose_analysis.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Returns true when [teardownMethod] contains a call to [teardownCall]
/// on a receiver named [receiverName].
///
/// Recognises both direct-method and cascade call forms anywhere in the method
/// body, including inside nested blocks such as `if`, `try`, `for`, etc.:
/// ```dart
/// _sub?.cancel();       // direct (null-aware)
/// _sub..cancel();       // cascade
/// ```
bool disposedInTeardown({
  required MethodDeclaration teardownMethod,
  required String receiverName,
  required String teardownCall,
}) {
  final body = teardownMethod.body;
  if (body is! BlockFunctionBody) return false;

  final visitor = _TeardownCallVisitor(receiverName, teardownCall);
  body.block.accept(visitor);
  return visitor.found;
}

/// Walks the entire AST subtree of a dispose/close/cancel method body and
/// reports whether a matching [MethodInvocation] or [CascadeExpression]
/// section is found anywhere, regardless of nesting depth.
class _TeardownCallVisitor extends RecursiveAstVisitor<void> {
  _TeardownCallVisitor(this._receiverName, this._teardownCall);

  final String _receiverName;
  final String _teardownCall;

  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!found) {
      if (node.methodName.name == _teardownCall) {
        final target = node.target;
        if (target is SimpleIdentifier && target.name == _receiverName) {
          found = true;
          return; // no need to descend further
        }
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitCascadeExpression(CascadeExpression node) {
    if (!found) {
      final target = node.target;
      if (target is SimpleIdentifier && target.name == _receiverName) {
        for (final section in node.cascadeSections) {
          if (section is MethodInvocation &&
              section.methodName.name == _teardownCall) {
            found = true;
            return;
          }
        }
      }
    }
    super.visitCascadeExpression(node);
  }
}

/// Finds the method named [methodName] declared directly on [cls], or `null`.
MethodDeclaration? findTeardownMethod(ClassDeclaration cls, String methodName) {
  for (final member in cls.members) {
    if (member is MethodDeclaration && member.name.lexeme == methodName) {
      return member;
    }
  }
  return null;
}

/// A single `<receiver>.addListener(<callback>)` invocation paired with the
/// syntactic identity of its callback argument, collected from a class body.
class AddListenerCall {
  AddListenerCall({
    required this.receiverName,
    required this.callbackSource,
    required this.invocation,
  });

  /// The simple name of the receiver (a field/identifier), e.g. `_controller`.
  final String receiverName;

  /// The normalised source text of the callback argument. Used only to confirm
  /// the SAME callback is passed to `removeListener` — we deliberately do NOT
  /// resolve aliases, so this is a conservative textual identity.
  final String callbackSource;

  /// The `addListener(...)` invocation node, for diagnostic positioning.
  final MethodInvocation invocation;
}

/// Collects every `<receiver>.addListener(<cb>)` invocation in [cls] whose
/// callback argument is a TEAR-OFF or NAMED REFERENCE (a [SimpleIdentifier],
/// [PrefixedIdentifier], or [PropertyAccess]) — NOT an inline closure.
///
/// This is intentionally conservative (see [missingRemoveListener] usage):
/// inline-closure callbacks have no stable referenceable identity, so they are
/// skipped entirely to avoid false positives — a closure passed to
/// `addListener` could never be matched to a `removeListener` anyway, and the
/// developer may be relying on the receiver's own disposal instead.
///
/// Only invocations whose receiver is a [SimpleIdentifier] (a bare field/local
/// reference) are collected, so we always have a stable receiver name to pair.
///
/// [excludeMethodNames] is the set of teardown method names (e.g. `{'dispose',
/// 'deactivate', 'close'}`) to SKIP when scanning. An `addListener` placed
/// INSIDE the teardown method itself (e.g. to do a one-time listen during
/// teardown) would otherwise produce a spurious "missing removeListener" lint
/// because the teardown body has no matching `removeListener` for that call.
List<AddListenerCall> collectPairableAddListeners(
  ClassDeclaration cls, {
  Set<String> excludeMethodNames = const {},
}) {
  final visitor = _AddListenerVisitor();
  for (final member in cls.members) {
    // Scan constructors and methods (initState, constructor bodies, helpers),
    // but SKIP teardown methods — addListener inside dispose/close is not a
    // listener that needs a paired removeListener (it's teardown-time work).
    if (member is MethodDeclaration) {
      if (excludeMethodNames.contains(member.name.lexeme)) continue;
      member.body.accept(visitor);
    } else if (member is ConstructorDeclaration) {
      member.body.accept(visitor);
    }
  }
  return visitor.calls;
}

class _AddListenerVisitor extends RecursiveAstVisitor<void> {
  final List<AddListenerCall> calls = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'addListener') {
      final target = node.target;
      final args = node.argumentList.arguments;
      if (target is SimpleIdentifier && args.length == 1) {
        final callback = args.first;
        // Conservative: only pair tear-offs / named references, never closures.
        final isPairable =
            callback is SimpleIdentifier ||
            callback is PrefixedIdentifier ||
            callback is PropertyAccess;
        if (isPairable) {
          calls.add(
            AddListenerCall(
              receiverName: target.name,
              callbackSource: callback.toSource(),
              invocation: node,
            ),
          );
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// Returns true when [teardownMethod] contains a
/// `<receiverName>.removeListener(<callbackSource>)` call matching both the
/// receiver name AND the exact callback source text. Conservative by design:
/// any matching removeListener on the same receiver+callback clears the flag.
bool hasMatchingRemoveListener({
  required MethodDeclaration teardownMethod,
  required String receiverName,
  required String callbackSource,
}) {
  final body = teardownMethod.body;
  if (body is! BlockFunctionBody) return false;
  final visitor = _RemoveListenerVisitor(receiverName, callbackSource);
  body.block.accept(visitor);
  return visitor.found;
}

class _RemoveListenerVisitor extends RecursiveAstVisitor<void> {
  _RemoveListenerVisitor(this._receiverName, this._callbackSource);

  final String _receiverName;
  final String _callbackSource;
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!found && node.methodName.name == 'removeListener') {
      final target = node.target;
      final args = node.argumentList.arguments;
      if (target is SimpleIdentifier &&
          target.name == _receiverName &&
          args.length == 1 &&
          args.first.toSource() == _callbackSource) {
        found = true;
        return;
      }
    }
    super.visitMethodInvocation(node);
  }
}
