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
MethodDeclaration? findTeardownMethod(
  ClassDeclaration cls,
  String methodName,
) {
  for (final member in cls.members) {
    if (member is MethodDeclaration && member.name.lexeme == methodName) {
      return member;
    }
  }
  return null;
}

/// Returns the names of non-static fields in [cls] that satisfy [typeTest].
List<String> ownedFieldNames({
  required ClassDeclaration cls,
  required bool Function(FieldDeclaration) typeTest,
}) {
  final names = <String>[];
  for (final member in cls.members) {
    if (member is FieldDeclaration && !member.isStatic) {
      if (typeTest(member)) {
        for (final variable in member.fields.variables) {
          names.add(variable.name.lexeme);
        }
      }
    }
  }
  return names;
}
