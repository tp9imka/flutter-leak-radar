// lib/src/util/dispose_analysis.dart
import 'package:analyzer/dart/ast/ast.dart';

/// Returns true when [teardownMethod] contains a call to [teardownCall]
/// on a receiver named [receiverName].
///
/// Recognises both direct-method and cascade call forms:
/// ```dart
/// _sub.cancel();        // direct
/// _sub?..cancel();      // cascade (null-aware)
/// ```
bool disposedInTeardown({
  required MethodDeclaration teardownMethod,
  required String receiverName,
  required String teardownCall,
}) {
  final body = teardownMethod.body;
  if (body is! BlockFunctionBody) return false;
  return _bodyContainsCall(body.block, receiverName, teardownCall);
}

bool _bodyContainsCall(
  Block block,
  String receiverName,
  String teardownCall,
) {
  for (final statement in block.statements) {
    if (statement is ExpressionStatement) {
      final expr = statement.expression;
      if (_isMatchingCall(expr, receiverName, teardownCall)) return true;
    }
  }
  return false;
}

bool _isMatchingCall(
  Expression expr,
  String receiverName,
  String teardownCall,
) {
  if (expr is MethodInvocation) {
    if (expr.methodName.name != teardownCall) return false;
    final target = expr.target;
    if (target is SimpleIdentifier && target.name == receiverName) return true;
  }
  if (expr is CascadeExpression) {
    final target = expr.target;
    if (target is SimpleIdentifier && target.name == receiverName) {
      for (final section in expr.cascadeSections) {
        if (section is MethodInvocation &&
            section.methodName.name == teardownCall) {
          return true;
        }
      }
    }
  }
  return false;
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
