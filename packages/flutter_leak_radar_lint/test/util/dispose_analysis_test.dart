// test/util/dispose_analysis_test.dart
//
// Unit tests for disposedInTeardown().
// Uses analyzer's parseString() to build real AST nodes without needing the
// full custom_lint rule-test harness.

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_leak_radar_lint/src/util/dispose_analysis.dart';
import 'package:test/test.dart';

/// Parses [source], finds the class named [className], and returns the
/// [MethodDeclaration] named [methodName], or throws if not found.
MethodDeclaration _findMethod(
  String source, {
  required String className,
  required String methodName,
}) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final unit = result.unit;

  for (final decl in unit.declarations) {
    if (decl is ClassDeclaration && decl.name.lexeme == className) {
      for (final member in decl.members) {
        if (member is MethodDeclaration &&
            member.name.lexeme == methodName) {
          return member;
        }
      }
    }
  }
  throw StateError(
    'Method $className.$methodName not found in parsed source',
  );
}

void main() {
  group('disposedInTeardown — top-level call', () {
    test('returns true when cancel is at the top level of dispose', () {
      const src = '''
class _S {
  dynamic _sub;
  void dispose() {
    _sub?.cancel();
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_sub',
          teardownCall: 'cancel',
        ),
        isTrue,
      );
    });

    test('returns false when field is never cancelled', () {
      const src = '''
class _S {
  dynamic _sub;
  void dispose() {
    // nothing
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_sub',
          teardownCall: 'cancel',
        ),
        isFalse,
      );
    });

    test('returns false when a DIFFERENT field is cancelled', () {
      const src = '''
class _S {
  dynamic _sub;
  dynamic _other;
  void dispose() {
    _other.cancel();
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_sub',
          teardownCall: 'cancel',
        ),
        isFalse,
      );
    });
  });

  group('disposedInTeardown — cascade form', () {
    test('returns true for cascade cancel at top level', () {
      const src = '''
class _S {
  dynamic _sub;
  void dispose() {
    _sub..cancel();
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_sub',
          teardownCall: 'cancel',
        ),
        isTrue,
      );
    });
  });

  group('disposedInTeardown — nested blocks (regression for flat-walk bug)', () {
    test('returns true when cancel is inside an if-block', () {
      const src = '''
class _S {
  dynamic _sub;
  bool _active = true;
  void dispose() {
    if (_active) {
      _sub.cancel();
    }
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_sub',
          teardownCall: 'cancel',
        ),
        isTrue,
        reason: 'cancel inside an if-block must not produce a false positive',
      );
    });

    test('returns true when cancel is inside a try-block', () {
      const src = '''
class _S {
  dynamic _sub;
  void dispose() {
    try {
      _sub.cancel();
    } catch (_) {}
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_sub',
          teardownCall: 'cancel',
        ),
        isTrue,
        reason: 'cancel inside a try-block must not produce a false positive',
      );
    });

    test('returns true when cancel is inside a for-loop', () {
      const src = '''
class _S {
  dynamic _sub;
  void dispose() {
    for (var i = 0; i < 1; i++) {
      _sub.cancel();
    }
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_sub',
          teardownCall: 'cancel',
        ),
        isTrue,
        reason: 'cancel inside a for-loop must not produce a false positive',
      );
    });

    test('returns false when no cancel anywhere in deeply nested body', () {
      const src = '''
class _S {
  dynamic _sub;
  void dispose() {
    if (true) {
      try {
        // no cancel here
      } catch (_) {}
    }
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_sub',
          teardownCall: 'cancel',
        ),
        isFalse,
      );
    });
  });

  group('disposedInTeardown — dispose (not cancel)', () {
    test('works with teardownCall=dispose for AnimationController', () {
      const src = '''
class _S {
  dynamic _ctrl;
  void dispose() {
    if (true) {
      _ctrl.dispose();
    }
  }
}
''';
      final method = _findMethod(src, className: '_S', methodName: 'dispose');
      expect(
        disposedInTeardown(
          teardownMethod: method,
          receiverName: '_ctrl',
          teardownCall: 'dispose',
        ),
        isTrue,
      );
    });
  });
}
