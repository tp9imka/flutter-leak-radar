// lib/src/rules/missing_remove_listener.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/dispose_analysis.dart';
import '../util/state_class.dart';
import '../util/type_checkers.dart';

/// Flags a `<listenable>.addListener(<callback>)` call that has no matching
/// `<listenable>.removeListener(<callback>)` in the teardown method.
///
/// THIS RULE IS DELIBERATELY CONSERVATIVE. False negatives are acceptable;
/// false positives are not. It only fires when ALL of the following hold:
///
/// 1. The class has a recognised teardown method (`dispose`/`deactivate` for a
///    [State] subclass, `close` for a `bloc` [BlocBase] subclass). Plain Dart
///    classes are not analysed — we cannot know their teardown contract.
/// 2. The `addListener` receiver is a bare field/identifier reference (a
///    [SimpleIdentifier]) whose static type is assignable to Flutter's
///    [Listenable] family (Listenable / ChangeNotifier / Animation). Unrelated
///    user-defined `addListener` methods are ignored.
/// 3. The callback is a TEAR-OFF or NAMED REFERENCE (e.g. `_onChange`,
///    `widget.onChange`), NOT an inline closure. Inline closures have no
///    referenceable identity to pair against — see [collectPairableAddListeners].
/// 4. There is NO `removeListener` for that exact receiver + callback anywhere
///    in ANY teardown method (top-level or nested in if/try/for).
///
/// Suppressions to avoid double-reporting / false positives:
/// - If the receiver field is itself a disposable controller (e.g.
///   AnimationController, ScrollController) it is already covered by
///   `undisposed_controller`; calling `removeListener` is redundant because
///   `dispose()` drops all listeners. We suppress here.
///
/// Severity: WARNING. Tier-C (message-only): removing a listener requires the
/// exact same callback reference, so there is no single safe automated edit.
class MissingRemoveListener extends DartLintRule {
  const MissingRemoveListener() : super(code: _code);

  static const _code = LintCode(
    name: 'missing_remove_listener',
    problemMessage:
        "addListener('{0}') on '{1}' has no matching removeListener in the teardown method.",
    correctionMessage:
        "Call '{1}.removeListener({0})' in dispose()/deactivate()/close() with the same callback reference.",
    errorSeverity: ErrorSeverity.WARNING,
  );

  // State teardown can legitimately remove listeners in either dispose() or
  // deactivate(); we accept a removeListener in any of these.
  static const _stateTeardowns = ['dispose', 'deactivate'];

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addClassDeclaration((cls) {
      final primaryTeardown = teardownMethodName(cls);
      if (primaryTeardown == null) return;

      // Gather every teardown method we will accept a removeListener in.
      final teardownNames = primaryTeardown == 'dispose'
          ? _stateTeardowns
          : [primaryTeardown];
      final teardowns = <MethodDeclaration>[
        for (final name in teardownNames)
          if (findTeardownMethod(cls, name) case final m?) m,
      ];

      final addCalls = collectPairableAddListeners(
        cls,
        excludeMethodNames: teardownNames.toSet(),
      );

      // Track which (receiver, callback) pairs we have already reported so a
      // listenable registered twice doesn't produce duplicate diagnostics.
      final reported = <String>{};

      for (final call in addCalls) {
        // (2) Receiver must be a Flutter Listenable.
        final receiverType = call.invocation.target?.staticType;
        if (!_isListenable(receiverType)) continue;

        // Suppress: receiver is a disposable controller already covered by
        // undisposed_controller; removeListener is redundant there.
        if (_isDisposableController(receiverType)) continue;

        // (4) Already removed for this exact receiver + callback?
        final removed = teardowns.any(
          (t) => hasMatchingRemoveListener(
            teardownMethod: t,
            receiverName: call.receiverName,
            callbackSource: call.callbackSource,
          ),
        );
        if (removed) continue;

        final key = '${call.receiverName}::${call.callbackSource}';
        if (!reported.add(key)) continue;

        reporter.atNode(
          call.invocation.methodName,
          _code,
          arguments: [call.callbackSource, call.receiverName],
        );
      }
    });
  }

  // Tier C: no auto-fix (callback identity makes a single safe edit impossible).
  @override
  List<Fix> getFixes() => [];
}

bool _isListenable(DartType? type) {
  if (type == null) return false;
  return kListenableTypes.any((checker) => checker.isAssignableFromType(type));
}

bool _isDisposableController(DartType? type) {
  if (type == null) return false;
  return kControllerTypes.any((checker) => checker.isAssignableFromType(type));
}
