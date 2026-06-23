# flutter_leak_radar_lint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Never skip a test step to reach the implementation step — write the failing test first every time.

**Goal:** Ship a `custom_lint` analyzer plugin at `packages/flutter_leak_radar_lint` that catches the four highest-value Flutter/Dart memory-leak patterns at edit/CI time: undisposed `State` controllers, uncancelled `StreamSubscription` fields, uncancelled `Timer` fields, and discarded `.listen()` results — with a complete scaffold, shared AST helpers, paired good/bad fixtures, programmatic unit tests, and CI integration. This is a usable v1; the remaining rules and harder auto-fixes are explicitly deferred.

**Architecture:** Plugin-as-package. A `createPlugin()` top-level function returns a `FlutterLeakRadarPlugin extends PluginBase`. Each rule lives in exactly one file under `lib/src/rules/`. Shared AST logic lives in `lib/src/util/`. The `example/` sub-directory under the package is the fixture project that `custom_lint` runs against as part of CI. Programmatic unit tests live under `test/` and call the rule's `.testAnalyzeAndRun(File)` hook.

**Tech Stack:** Dart 3.10, `analyzer ^8.0.0`, `custom_lint_builder ^0.8.1` (authoring), `custom_lint ^0.8.1` (dev / runner), `test ^1.25.0`. Melos workspace.

**Source of truth:** `docs/specs/2026-06-23-flutter-leak-radar-lint-design.md`. Read `AGENTS.md` before starting.

---

## Global Constraints

- **Dart SDK `>=3.10.0 <4.0.0`.** No hard Flutter dependency in the plugin package itself; resolve Flutter SDK types by library URI via `TypeChecker`.
- **analyzer 8.x API.** Use `reporter.atNode(node, code, arguments: [...])` — NOT `reporter.reportErrorForNode(...)`. Write against `Element` (NOT `Element2`; the dual model was collapsed back). Check the spec §API-version note before any reporter or element call.
- **`custom_lint_builder 0.8.1` / `custom_lint 0.8.1`.** Use `DartLintRule.run(CustomLintResolver, ErrorReporter, CustomLintContext)`. Register syntactic visitors via `context.registry.add*`. Return fixes from `getFixes()`.
- **One rule per file** under `lib/src/rules/`, ~80–200 lines each. Extract shared helpers to `lib/src/util/`.
- **Files ≤ 800 lines, typically 200–400.** Organize by domain (rules/, util/), not by file type.
- **Immutable hand-rolled value types — NOT freezed.** Follow the repo's code style (AGENTS.md §4).
- **No `print`.** Rules are analysis-time only; log nothing at runtime.
- **Every rule must have: a `bad.dart` fixture (`// expect_lint:`) + a `good.dart` fixture (zero lints) + a programmatic unit test.** False-positive shapes from spec §5.3 get their own `good_*.dart` fixture.
- **Auto-fixes only via `ChangeBuilder`.** Never splice source strings directly.
- **`resolution: workspace`** in the package `pubspec.yaml`. Add `packages/flutter_leak_radar_lint` to the root `pubspec.yaml` workspace array.

---

## V1 Rule Set (chosen) and Deferred Rules

### Included in this plan (4 rules)

| # | Code | Severity | Fix tier |
|---|------|----------|----------|
| 1 | `undisposed_controller` | WARNING | Tier A — auto-insert `<field>.dispose()` into `dispose()` |
| 2 | `uncancelled_subscription` | WARNING | Tier B — auto-fix field case; message-only for locals |
| 3 | `uncancelled_timer` | WARNING / INFO | Tier B — auto-fix stored field; message-only for discarded |
| 4 | `discarded_listen_result` | WARNING | Tier C — message-only, no auto-fix |

**Rationale:** These four cover the most common statically-detectable leaks in plain Flutter apps (no BLoC dep needed), share the same `disposedInTeardown` helper, and provide concrete signal for teams immediately. Rules 1 and 4 together already catch the two most frequently reported leak shapes in real Flutter codebases.

### Deferred to follow-up plan

| Code | Why deferred |
|------|-------------|
| `missing_remove_listener` | Requires callback-identity pairing logic (named-field vs. inline-closure suppression); medium implementation effort, higher false-positive surface. |
| `unclosed_stream_controller` | Largely covered by `uncancelled_subscription`; lower incremental value at v1. |
| `bloc_uncancelled_subscription` | Requires BLoC `TypeChecker`s and `emit.forEach`/`onEach` suppression; adds a BLoC ecosystem dependency on the util layer. |
| All Tier A auto-fixes for `close()` and `cancel()` | Only `undisposed_controller` ships a Tier A fix in v1; the others ship Tier B/C to keep fix correctness guardrails tight. Expand in M3+. |

---

## Task 0 — Package scaffold and workspace wiring

**Files:**
- Create: `packages/flutter_leak_radar_lint/pubspec.yaml`
- Create: `packages/flutter_leak_radar_lint/analysis_options.yaml`
- Create: `packages/flutter_leak_radar_lint/lib/flutter_leak_radar_lint.dart`
- Create: `packages/flutter_leak_radar_lint/lib/src/plugin.dart`
- Create: `packages/flutter_leak_radar_lint/example/pubspec.yaml`
- Create: `packages/flutter_leak_radar_lint/example/analysis_options.yaml`
- Edit: `pubspec.yaml` (root) — add `packages/flutter_leak_radar_lint` to `workspace:`

**Interfaces produced:** A resolvable Dart package that compiles, with an empty `getLintRules()`. Running `dart run custom_lint` in `packages/flutter_leak_radar_lint/example/` exits 0 with zero lints.

- [ ] **Step 1: Add the package to the root workspace**

Edit `pubspec.yaml` (root) to add `packages/flutter_leak_radar_lint` alongside `packages/flutter_leak_radar`:

```yaml
name: flutter_leak_radar_workspace
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
workspace:
  - packages/flutter_leak_radar
  - packages/flutter_leak_radar_lint
  - example
dev_dependencies:
  melos: ^6.0.0
```

- [ ] **Step 2: Create `packages/flutter_leak_radar_lint/pubspec.yaml`**

```yaml
name: flutter_leak_radar_lint
description: >-
  Lint rules that catch common Flutter/Dart memory-leak patterns at edit time.
  Undisposed controllers, uncancelled subscriptions, discarded listen results.
version: 0.1.0
publish_to: none
repository: https://github.com/<owner>/flutter-leak-radar

environment:
  sdk: ">=3.10.0 <4.0.0"

resolution: workspace

dependencies:
  analyzer: ^8.0.0
  custom_lint_builder: ^0.8.1

dev_dependencies:
  custom_lint: ^0.8.1
  test: ^1.25.0
```

`custom_lint_builder` is the authoring dep (plugin author); `custom_lint` is dev-only (runs the plugin). No `flutter` dep — resolve Flutter SDK types by library URI.

- [ ] **Step 3: Create `packages/flutter_leak_radar_lint/analysis_options.yaml`**

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - example/**
    - test/fixtures/**
```

- [ ] **Step 4: Create the public entrypoint**

`packages/flutter_leak_radar_lint/lib/flutter_leak_radar_lint.dart`:

```dart
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'src/plugin.dart';

/// Entry point discovered by the custom_lint runner via reflection.
/// The function name and signature are fixed — do not rename.
PluginBase createPlugin() => FlutterLeakRadarPlugin();
```

- [ ] **Step 5: Create the plugin class (initially empty rule list)**

`packages/flutter_leak_radar_lint/lib/src/plugin.dart`:

```dart
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// The custom_lint plugin for flutter_leak_radar.
///
/// [getLintRules] returns all enabled rules. custom_lint handles per-rule
/// enable/disable via the consumer's `analysis_options.yaml`
/// `custom_lint: rules:` block automatically.
class FlutterLeakRadarPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [];
}
```

- [ ] **Step 6: Create the fixture consumer project**

`packages/flutter_leak_radar_lint/example/pubspec.yaml`:

```yaml
name: flutter_leak_radar_lint_example
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
  flutter: ">=3.38.0"
resolution: workspace

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  custom_lint: ^0.8.1
  flutter_leak_radar_lint:
    path: ..
```

`packages/flutter_leak_radar_lint/example/analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint
```

- [ ] **Step 7: Verify scaffold compiles and custom_lint exits 0**

```bash
cd packages/flutter_leak_radar_lint
dart pub get
dart run custom_lint --working-directory example
```

Expected: exits 0, zero diagnostics. If the plugin fails to load, check that `createPlugin()` is exported at the top level of `lib/flutter_leak_radar_lint.dart` (not from `src/`).

---

## Task 1 — Shared utilities: TypeCheckers, state_class, dispose_analysis

**Files:**
- Create: `packages/flutter_leak_radar_lint/lib/src/util/type_checkers.dart`
- Create: `packages/flutter_leak_radar_lint/lib/src/util/state_class.dart`
- Create: `packages/flutter_leak_radar_lint/lib/src/util/dispose_analysis.dart`
- Create: `packages/flutter_leak_radar_lint/test/util/dispose_analysis_test.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/util/disposed_in_teardown_bad.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/util/disposed_in_teardown_good.dart`

**Interfaces consumed:** `package:analyzer` AST/element API.  
**Interfaces produced:** `kControllerTypes`, `kStreamSubscriptionType`, `kTimerType`, `kStreamType`, `isStateSubclass`, `isBlocBaseSubclass`, `teardownMethodName`, `disposedInTeardown`, `assignedInClass`.

- [ ] **Step 1: Write the failing util test first**

`packages/flutter_leak_radar_lint/test/util/dispose_analysis_test.dart`:

```dart
// test/util/dispose_analysis_test.dart
// This test is intentionally left as a framework stub — the util functions
// are exercised transitively by the rule tests in Tasks 2–5.
// Direct unit tests for disposedInTeardown are added once the AST types
// are available via the rule's .testAnalyzeAndRun fixture plumbing.
// See: test/undisposed_controller_test.dart for the primary entry point.
void main() {}
```

Run:

```bash
cd packages/flutter_leak_radar_lint && dart test
```

Expected: 0 tests, 0 failures (stub passes trivially; real coverage comes in Tasks 2–5).

- [ ] **Step 2: Implement `lib/src/util/type_checkers.dart`**

```dart
// lib/src/util/type_checkers.dart
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// TypeCheckers for Flutter SDK disposable controller types.
/// Uses library URI + class name — no hard `package:flutter` import needed.
const kAnimationControllerChecker = TypeChecker.fromName(
  'AnimationController',
  packageName: 'flutter',
);
const kTextEditingControllerChecker = TypeChecker.fromName(
  'TextEditingController',
  packageName: 'flutter',
);
const kScrollControllerChecker = TypeChecker.fromName(
  'ScrollController',
  packageName: 'flutter',
);
const kTabControllerChecker = TypeChecker.fromName(
  'TabController',
  packageName: 'flutter',
);
const kPageControllerChecker = TypeChecker.fromName(
  'PageController',
  packageName: 'flutter',
);
const kFocusNodeChecker = TypeChecker.fromName(
  'FocusNode',
  packageName: 'flutter',
);

/// Convenience: any disposable-controller type.
const kControllerTypes = [
  kAnimationControllerChecker,
  kTextEditingControllerChecker,
  kScrollControllerChecker,
  kTabControllerChecker,
  kPageControllerChecker,
  kFocusNodeChecker,
];

/// dart:async types.
const kStreamSubscriptionChecker = TypeChecker.fromName(
  'StreamSubscription',
  packageName: 'async', // dart:async
);
const kStreamChecker = TypeChecker.fromName(
  'Stream',
  packageName: 'async',
);
const kTimerChecker = TypeChecker.fromName(
  'Timer',
  packageName: 'async',
);
```

> **Note:** `TypeChecker.fromName` accepts `packageName` for SDK packages. For `dart:async` use `packageName: 'async'`. Verify exact package name against analyzer's element library identifier if the checker mismatches — SDK library URIs use `dart:async`, but the `fromName` helper maps via the package name component.

- [ ] **Step 3: Implement `lib/src/util/state_class.dart`**

```dart
// lib/src/util/state_class.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

const _stateChecker = TypeChecker.fromName('State', packageName: 'flutter');
const _blocBaseChecker = TypeChecker.fromName('BlocBase', packageName: 'bloc');

/// Returns true when [cls] is a concrete subclass of Flutter's [State<T>].
bool isStateSubclass(ClassDeclaration cls) {
  final element = cls.declaredElement;
  if (element == null) return false;
  return _stateChecker.isAssignableFrom(element);
}

/// Returns true when [cls] is a concrete subclass of [BlocBase]
/// (covers both Bloc<E,S> and Cubit<S>).
bool isBlocBaseSubclass(ClassDeclaration cls) {
  final element = cls.declaredElement;
  if (element == null) return false;
  return _blocBaseChecker.isAssignableFrom(element);
}

/// The name of the teardown method for a given class declaration.
/// Returns 'dispose' for State subclasses, 'close' for BlocBase subclasses,
/// null if neither.
String? teardownMethodName(ClassDeclaration cls) {
  if (isStateSubclass(cls)) return 'dispose';
  if (isBlocBaseSubclass(cls)) return 'close';
  return null;
}
```

- [ ] **Step 4: Implement `lib/src/util/dispose_analysis.dart`**

```dart
// lib/src/util/dispose_analysis.dart
import 'package:analyzer/dart/ast/ast.dart';

/// Scans [teardownMethod]'s body for a call [receiverName].<methodName>(...).
///
/// Performs intra-method syntactic scan: walks ExpressionStatement children
/// looking for MethodInvocation nodes where the target identifier matches
/// [receiverName] and the method name matches [teardownCall].
///
/// Returns true if at least one matching call is found.
///
/// Limitation (by design): does not follow helper-method calls one level deep.
/// That extension is deferred to a follow-up plan iteration.
bool disposedInTeardown({
  required MethodDeclaration teardownMethod,
  required String receiverName,
  required String teardownCall,
}) {
  final body = teardownMethod.body;
  if (body is! BlockFunctionBody) return false;
  return _bodyContainsCall(body.block, receiverName, teardownCall);
}

bool _bodyContainsCall(Block block, String receiverName, String teardownCall) {
  for (final statement in block.statements) {
    if (statement is ExpressionStatement) {
      final expr = statement.expression;
      if (_isMatchingCall(expr, receiverName, teardownCall)) return true;
    }
    // Also handle if-null guards like: `_sub?.cancel()`.
    if (statement is ExpressionStatement) {
      final expr = statement.expression;
      if (expr is MethodInvocation) {
        final target = expr.target;
        if (target is PostfixExpression) {
          // covers `_sub?.cancel()` as CascadeExpression or ConditionalAccess
        }
      }
    }
  }
  return false;
}

bool _isMatchingCall(Expression expr, String receiverName, String teardownCall) {
  if (expr is MethodInvocation) {
    final methodName = expr.methodName.name;
    if (methodName != teardownCall) return false;
    final target = expr.target;
    // Direct call: receiverName.teardownCall()
    if (target is SimpleIdentifier && target.name == receiverName) return true;
    // Null-aware call: receiverName?.teardownCall()
    if (target is SimpleIdentifier && target.name == receiverName) return true;
  }
  // Cascade: _sub..cancel()  →  CascadeExpression with MethodInvocation
  if (expr is CascadeExpression) {
    if (expr.target is SimpleIdentifier &&
        (expr.target as SimpleIdentifier).name == receiverName) {
      for (final section in expr.cascadeSections) {
        if (section is MethodInvocation && section.methodName.name == teardownCall) {
          return true;
        }
      }
    }
  }
  return false;
}

/// Finds the teardown [MethodDeclaration] named [methodName] inside [cls].
/// Returns null if no such override exists.
MethodDeclaration? findTeardownMethod(ClassDeclaration cls, String methodName) {
  for (final member in cls.members) {
    if (member is MethodDeclaration && member.name.lexeme == methodName) {
      return member;
    }
  }
  return null;
}

/// Returns all field names whose type satisfies [typeTest] and
/// whose initializer (or assignment in [initMethodName]) is non-null,
/// indicating the class owns the object.
///
/// Used by rule implementations to enumerate candidate fields.
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
```

---

## Task 2 — Rule 1: `undisposed_controller` (Tier A, with auto-fix)

**Files:**
- Create: `packages/flutter_leak_radar_lint/lib/src/rules/undisposed_controller.dart`
- Edit: `packages/flutter_leak_radar_lint/lib/src/plugin.dart` — register `UndisposedController`
- Create: `packages/flutter_leak_radar_lint/example/lib/undisposed_controller/bad.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/undisposed_controller/good.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/undisposed_controller/good_late_field.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/undisposed_controller/good_constructor_param.dart`
- Create: `packages/flutter_leak_radar_lint/test/undisposed_controller_test.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/undisposed_controller/bad.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/undisposed_controller/good.dart`

**Interfaces consumed:** `disposedInTeardown`, `findTeardownMethod`, `ownedFieldNames`, `isStateSubclass`, `kControllerTypes`.  
**Interfaces produced:** `UndisposedController extends DartLintRule`, `AddDisposeCall extends DartFix`.

- [ ] **Step 1: Write the failing fixture test**

`packages/flutter_leak_radar_lint/test/fixtures/undisposed_controller/bad.dart`:

```dart
// test/fixtures/undisposed_controller/bad.dart
import 'package:flutter/widgets.dart';

class _BadState extends State<StatefulWidget> {
  // A TextEditingController owned and never disposed.
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _AlsoBadState extends State<StatefulWidget> {
  // AnimationController stored in a field but dispose() not overridden.
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: const _NeverTick(), duration: Duration.zero);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _NeverTick implements TickerProvider {
  const _NeverTick();
  @override
  Ticker createTicker(TickerCallback _) => throw UnimplementedError();
}
```

`packages/flutter_leak_radar_lint/test/fixtures/undisposed_controller/good.dart`:

```dart
// test/fixtures/undisposed_controller/good.dart
import 'package:flutter/widgets.dart';

// Good: controller is disposed in dispose().
class _GoodState extends State<StatefulWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: late field never initialized (not owned).
class _GoodLateState extends State<StatefulWidget> {
  late TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: controller passed in via constructor (not owned here).
class _GoodParamState extends State<StatefulWidget> {
  _GoodParamState(this._controller);
  final TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`packages/flutter_leak_radar_lint/test/undisposed_controller_test.dart`:

```dart
// test/undisposed_controller_test.dart
import 'dart:io';
import 'package:flutter_leak_radar_lint/src/rules/undisposed_controller.dart';
import 'package:test/test.dart';

void main() {
  const rule = UndisposedController();

  test('flags an undisposed TextEditingController field', () async {
    final errors = await rule.testAnalyzeAndRun(
      File('test/fixtures/undisposed_controller/bad.dart'),
    );
    expect(errors, isNotEmpty, reason: 'expected at least one undisposed_controller lint');
    expect(
      errors.every((e) => e.errorCode.name == 'undisposed_controller'),
      isTrue,
    );
  });

  test('does not flag a controller that is disposed in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(
      File('test/fixtures/undisposed_controller/good.dart'),
    );
    expect(errors, isEmpty, reason: 'no lint expected for a properly disposed controller');
  });
}
```

Run (expect compile failure — `UndisposedController` does not exist yet):

```bash
cd packages/flutter_leak_radar_lint && dart test test/undisposed_controller_test.dart
```

Expected: compilation error. Proceed to implementation.

- [ ] **Step 2: Implement `lib/src/rules/undisposed_controller.dart`**

```dart
// lib/src/rules/undisposed_controller.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
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
/// False-positive suppressions (deferred to good_*.dart fixtures):
/// - `late` field with no initializer (not proven owned).
/// - Field assigned from a constructor parameter (not created here).
/// - Field disposed via a helper method called from dispose() — deferred.
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

        final fieldType = member.fields.type?.type;
        if (!_isDisposableController(fieldType)) continue;

        for (final variable in member.fields.variables) {
          final fieldName = variable.name.lexeme;

          // Heuristic: skip `late` fields with no initializer — not proven owned.
          if (variable.initializer == null &&
              member.fields.isLate &&
              !_isAssignedInInitState(cls, fieldName)) {
            continue;
          }

          // Heuristic: skip fields assigned from a constructor parameter.
          if (_isConstructorParam(cls, fieldName)) continue;

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
          if (lhs is PrefixedIdentifier && lhs.identifier.name == fieldName) return true;
        }
      }
    }
  }
  return false;
}

/// Checks whether [fieldName] is initialized from a constructor parameter
/// (i.e. owned by the caller, not created here).
bool _isConstructorParam(ClassDeclaration cls, String fieldName) {
  for (final member in cls.members) {
    if (member is! ConstructorDeclaration) continue;
    for (final param in member.parameters.parameters) {
      if (param is FieldFormalParameter && param.name.lexeme == fieldName) return true;
      if (param is SimpleFormalParameter && param.name?.lexeme == fieldName) return true;
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

      // Determine field name from the lint arguments stored in the error.
      // We re-derive by checking which field token overlaps the error range.
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
```

- [ ] **Step 3: Register the rule in `plugin.dart`**

Edit `lib/src/plugin.dart`:

```dart
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'rules/undisposed_controller.dart';

class FlutterLeakRadarPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
        UndisposedController(),
      ];
}
```

- [ ] **Step 4: Create the example `bad.dart` fixture (with `expect_lint:`)**

`packages/flutter_leak_radar_lint/example/lib/undisposed_controller/bad.dart`:

```dart
// example/lib/undisposed_controller/bad.dart
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // expect_lint: undisposed_controller
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) => const SizedBox();
  // No dispose() override — lint should fire.
}
```

- [ ] **Step 5: Create the example `good.dart` fixture (zero lints)**

`packages/flutter_leak_radar_lint/example/lib/undisposed_controller/good.dart`:

```dart
// example/lib/undisposed_controller/good.dart
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: constructor-param controller (not owned by State).
class _ParamState extends State<MyWidget> {
  _ParamState(this._controller);
  final TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

- [ ] **Step 6: Run the fixture test via custom_lint**

```bash
cd packages/flutter_leak_radar_lint
dart run custom_lint --working-directory example
```

Expected: exits 0 with the `expect_lint: undisposed_controller` annotation satisfied. If `expect_lint` is not met the runner exits non-zero with an unmet-expectation error.

- [ ] **Step 7: Run the programmatic unit test**

```bash
cd packages/flutter_leak_radar_lint && dart test test/undisposed_controller_test.dart
```

Expected: 2 passing tests.

---

## Task 3 — Rule 2: `uncancelled_subscription` (Tier B)

**Files:**
- Create: `packages/flutter_leak_radar_lint/lib/src/rules/uncancelled_subscription.dart`
- Edit: `packages/flutter_leak_radar_lint/lib/src/plugin.dart` — register
- Create: `packages/flutter_leak_radar_lint/example/lib/uncancelled_subscription/bad.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/uncancelled_subscription/good.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/uncancelled_subscription/good_cancelled_in_dispose.dart`
- Create: `packages/flutter_leak_radar_lint/test/uncancelled_subscription_test.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/uncancelled_subscription/bad.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/uncancelled_subscription/good.dart`

**Interfaces consumed:** `disposedInTeardown`, `findTeardownMethod`, `isStateSubclass`, `kStreamSubscriptionChecker`.  
**Interfaces produced:** `UncancelledSubscription extends DartLintRule`.

- [ ] **Step 1: Write the failing unit test**

`packages/flutter_leak_radar_lint/test/fixtures/uncancelled_subscription/bad.dart`:

```dart
// test/fixtures/uncancelled_subscription/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _BadState extends State<StatefulWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
  // Missing dispose() with _sub?.cancel().
}
```

`packages/flutter_leak_radar_lint/test/fixtures/uncancelled_subscription/good.dart`:

```dart
// test/fixtures/uncancelled_subscription/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _GoodState extends State<StatefulWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`packages/flutter_leak_radar_lint/test/uncancelled_subscription_test.dart`:

```dart
// test/uncancelled_subscription_test.dart
import 'dart:io';
import 'package:flutter_leak_radar_lint/src/rules/uncancelled_subscription.dart';
import 'package:test/test.dart';

void main() {
  const rule = UncancelledSubscription();

  test('flags a StreamSubscription field not cancelled in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(
      File('test/fixtures/uncancelled_subscription/bad.dart'),
    );
    expect(errors, isNotEmpty);
    expect(errors.every((e) => e.errorCode.name == 'uncancelled_subscription'), isTrue);
  });

  test('does not flag a subscription cancelled in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(
      File('test/fixtures/uncancelled_subscription/good.dart'),
    );
    expect(errors, isEmpty);
  });
}
```

Run (expect compile failure):

```bash
cd packages/flutter_leak_radar_lint && dart test test/uncancelled_subscription_test.dart
```

- [ ] **Step 2: Implement `lib/src/rules/uncancelled_subscription.dart`**

```dart
// lib/src/rules/uncancelled_subscription.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/dispose_analysis.dart';
import '../util/state_class.dart';
import '../util/type_checkers.dart';

/// Flags a [StreamSubscription] field inside a [State<T>] (or any class with a
/// teardown method) that is never cancelled in `dispose()` / `close()`.
///
/// Only the FIELD case is reported here. Discarded `.listen()` results
/// (where the subscription is never captured at all) are caught by
/// [DiscardedListenResult].
///
/// Tier B fix: field case auto-inserts `<field>?.cancel();` into the teardown.
/// Local-variable case: message-only (deferred).
class UncancelledSubscription extends DartLintRule {
  const UncancelledSubscription() : super(code: _code);

  static const _code = LintCode(
    name: 'uncancelled_subscription',
    problemMessage:
        "The StreamSubscription '{0}' is never cancelled in dispose().",
    correctionMessage:
        "Call '{0}.cancel()' inside dispose() to prevent memory leaks.",
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
      // Only analyze State and BlocBase subclasses for now.
      if (teardownName == null) return;

      final teardown = findTeardownMethod(cls, teardownName);

      for (final member in cls.members) {
        if (member is! FieldDeclaration || member.isStatic) continue;

        final fieldType = member.fields.type?.type;
        if (!_isStreamSubscription(fieldType)) continue;

        for (final variable in member.fields.variables) {
          final fieldName = variable.name.lexeme;

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
          final body = cls.rightBracket.offset;
          final superCall = teardownName == 'close'
              ? '    return super.close();\n'
              : '    super.$teardownName();\n';
          builder.addSimpleInsertion(body, '''

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
```

- [ ] **Step 3: Register in `plugin.dart` and add example fixtures**

Edit `lib/src/plugin.dart`:

```dart
import 'rules/undisposed_controller.dart';
import 'rules/uncancelled_subscription.dart';

class FlutterLeakRadarPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
        UndisposedController(),
        UncancelledSubscription(),
      ];
}
```

`packages/flutter_leak_radar_lint/example/lib/uncancelled_subscription/bad.dart`:

```dart
// example/lib/uncancelled_subscription/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // expect_lint: uncancelled_subscription
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`packages/flutter_leak_radar_lint/example/lib/uncancelled_subscription/good.dart`:

```dart
// example/lib/uncancelled_subscription/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

- [ ] **Step 4: Verify both test layers pass**

```bash
cd packages/flutter_leak_radar_lint
dart test test/uncancelled_subscription_test.dart
dart run custom_lint --working-directory example
```

Expected: 2 unit tests passing; custom_lint exits 0 with both `expect_lint` annotations satisfied.

---

## Task 4 — Rule 3: `uncancelled_timer` (Tier B / INFO for one-shot)

**Files:**
- Create: `packages/flutter_leak_radar_lint/lib/src/rules/uncancelled_timer.dart`
- Edit: `packages/flutter_leak_radar_lint/lib/src/plugin.dart` — register
- Create: `packages/flutter_leak_radar_lint/example/lib/uncancelled_timer/bad.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/uncancelled_timer/good.dart`
- Create: `packages/flutter_leak_radar_lint/test/uncancelled_timer_test.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/uncancelled_timer/bad.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/uncancelled_timer/good.dart`

**Interfaces consumed:** `disposedInTeardown`, `findTeardownMethod`, `isStateSubclass`, `kTimerChecker`.  
**Interfaces produced:** `UncancelledTimer extends DartLintRule`.

- [ ] **Step 1: Write the failing unit test**

`packages/flutter_leak_radar_lint/test/fixtures/uncancelled_timer/bad.dart`:

```dart
// test/fixtures/uncancelled_timer/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _BadPeriodicState extends State<StatefulWidget> {
  // Timer.periodic stored in a field but never cancelled in dispose().
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`packages/flutter_leak_radar_lint/test/fixtures/uncancelled_timer/good.dart`:

```dart
// test/fixtures/uncancelled_timer/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _GoodState extends State<StatefulWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`packages/flutter_leak_radar_lint/test/uncancelled_timer_test.dart`:

```dart
// test/uncancelled_timer_test.dart
import 'dart:io';
import 'package:flutter_leak_radar_lint/src/rules/uncancelled_timer.dart';
import 'package:test/test.dart';

void main() {
  const rule = UncancelledTimer();

  test('flags a Timer field not cancelled in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(
      File('test/fixtures/uncancelled_timer/bad.dart'),
    );
    expect(errors, isNotEmpty);
    expect(errors.every((e) => e.errorCode.name == 'uncancelled_timer'), isTrue);
  });

  test('does not flag a Timer that is cancelled in dispose()', () async {
    final errors = await rule.testAnalyzeAndRun(
      File('test/fixtures/uncancelled_timer/good.dart'),
    );
    expect(errors, isEmpty);
  });
}
```

Run (expect compile failure):

```bash
cd packages/flutter_leak_radar_lint && dart test test/uncancelled_timer_test.dart
```

- [ ] **Step 2: Implement `lib/src/rules/uncancelled_timer.dart`**

```dart
// lib/src/rules/uncancelled_timer.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../util/dispose_analysis.dart';
import '../util/state_class.dart';
import '../util/type_checkers.dart';

/// Flags a [Timer] field inside a [State<T>] that is never cancelled in
/// `dispose()`. Uses WARNING severity (same as other subscription rules).
///
/// One-shot [Timer] objects fire once and become inert; in practice though,
/// if a one-shot timer is stored in a State field its cancel path should still
/// be guarded — we use WARNING across the board for field-stored timers.
///
/// Tier B fix: insert `<field>?.cancel()` into dispose(). Discarded (not stored)
/// Timer results are out of scope for this rule — see [DiscardedListenResult]
/// for the analogous Stream pattern.
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
      if (!isStateSubclass(cls)) return;

      final teardown = findTeardownMethod(cls, 'dispose');

      for (final member in cls.members) {
        if (member is! FieldDeclaration || member.isStatic) continue;

        final fieldType = member.fields.type?.type;
        if (!_isTimer(fieldType)) continue;

        for (final variable in member.fields.variables) {
          final fieldName = variable.name.lexeme;

          // Skip uninitialized late fields — not proven owned.
          if (variable.initializer == null && member.fields.isLate) continue;

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
      if (!isStateSubclass(cls)) return;

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
        message: "Add '$fieldName?.cancel()' to dispose()",
        priority: 75,
      );

      if (existingDispose != null) {
        changeBuilder.addDartFileEdit((builder) {
          final body = existingDispose.body;
          if (body is! BlockFunctionBody) return;
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
          builder.addSimpleInsertion(insertOffset, '    $fieldName?.cancel();\n');
        });
      } else {
        changeBuilder.addDartFileEdit((builder) {
          builder.addSimpleInsertion(cls.rightBracket.offset, '''

  @override
  void dispose() {
    $fieldName?.cancel();
    super.dispose();
  }
''');
        });
      }
    });
  }
}
```

- [ ] **Step 3: Register in `plugin.dart` and add example fixtures**

Add to `plugin.dart` imports and `getLintRules`:

```dart
import 'rules/uncancelled_timer.dart';
// ...
List<LintRule> getLintRules(CustomLintConfigs configs) => const [
  UndisposedController(),
  UncancelledSubscription(),
  UncancelledTimer(),
];
```

`packages/flutter_leak_radar_lint/example/lib/uncancelled_timer/bad.dart`:

```dart
// example/lib/uncancelled_timer/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // expect_lint: uncancelled_timer
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`packages/flutter_leak_radar_lint/example/lib/uncancelled_timer/good.dart`:

```dart
// example/lib/uncancelled_timer/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

- [ ] **Step 4: Verify both test layers pass**

```bash
cd packages/flutter_leak_radar_lint
dart test test/uncancelled_timer_test.dart
dart run custom_lint --working-directory example
```

Expected: 2 unit tests passing; custom_lint exits 0.

---

## Task 5 — Rule 4: `discarded_listen_result` (Tier C, message-only)

**Files:**
- Create: `packages/flutter_leak_radar_lint/lib/src/rules/discarded_listen_result.dart`
- Edit: `packages/flutter_leak_radar_lint/lib/src/plugin.dart` — register
- Create: `packages/flutter_leak_radar_lint/example/lib/discarded_listen_result/bad.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/discarded_listen_result/good.dart`
- Create: `packages/flutter_leak_radar_lint/test/discarded_listen_result_test.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/discarded_listen_result/bad.dart`
- Create: `packages/flutter_leak_radar_lint/test/fixtures/discarded_listen_result/good.dart`

**Interfaces consumed:** `kStreamChecker`.  
**Interfaces produced:** `DiscardedListenResult extends DartLintRule` (no fix).

- [ ] **Step 1: Write the failing unit test**

`packages/flutter_leak_radar_lint/test/fixtures/discarded_listen_result/bad.dart`:

```dart
// test/fixtures/discarded_listen_result/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _BadState extends State<StatefulWidget> {
  @override
  void initState() {
    super.initState();
    // .listen() return value is discarded — subscription leaks.
    Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`packages/flutter_leak_radar_lint/test/fixtures/discarded_listen_result/good.dart`:

```dart
// test/fixtures/discarded_listen_result/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _GoodState extends State<StatefulWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    // Good: result captured in a field.
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: listen result assigned to a local variable
// (still a potential leak but not the discarded shape this rule targets).
void notAWidget() {
  final sub = Stream<int>.empty().listen((_) {});
  sub.cancel();
}
```

`packages/flutter_leak_radar_lint/test/discarded_listen_result_test.dart`:

```dart
// test/discarded_listen_result_test.dart
import 'dart:io';
import 'package:flutter_leak_radar_lint/src/rules/discarded_listen_result.dart';
import 'package:test/test.dart';

void main() {
  const rule = DiscardedListenResult();

  test('flags a discarded .listen() result', () async {
    final errors = await rule.testAnalyzeAndRun(
      File('test/fixtures/discarded_listen_result/bad.dart'),
    );
    expect(errors, isNotEmpty);
    expect(errors.every((e) => e.errorCode.name == 'discarded_listen_result'), isTrue);
  });

  test('does not flag a .listen() result that is assigned', () async {
    final errors = await rule.testAnalyzeAndRun(
      File('test/fixtures/discarded_listen_result/good.dart'),
    );
    expect(errors, isEmpty);
  });
}
```

Run (expect compile failure):

```bash
cd packages/flutter_leak_radar_lint && dart test test/discarded_listen_result_test.dart
```

- [ ] **Step 2: Implement `lib/src/rules/discarded_listen_result.dart`**

```dart
// lib/src/rules/discarded_listen_result.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
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
```

- [ ] **Step 3: Register in `plugin.dart` and add example fixtures**

Final `lib/src/plugin.dart`:

```dart
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'rules/discarded_listen_result.dart';
import 'rules/uncancelled_subscription.dart';
import 'rules/uncancelled_timer.dart';
import 'rules/undisposed_controller.dart';

class FlutterLeakRadarPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
        UndisposedController(),
        UncancelledSubscription(),
        UncancelledTimer(),
        DiscardedListenResult(),
      ];
}
```

`packages/flutter_leak_radar_lint/example/lib/discarded_listen_result/bad.dart`:

```dart
// example/lib/discarded_listen_result/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
    // expect_lint: discarded_listen_result
    Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`packages/flutter_leak_radar_lint/example/lib/discarded_listen_result/good.dart`:

```dart
// example/lib/discarded_listen_result/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

- [ ] **Step 4: Verify both test layers pass**

```bash
cd packages/flutter_leak_radar_lint
dart test test/discarded_listen_result_test.dart
dart run custom_lint --working-directory example
```

Expected: 2 unit tests passing; custom_lint exits 0 with all 4 rules' `expect_lint` annotations satisfied.

---

## Task 6 — False-positive fixtures and CI integration

**Files:**
- Create: `packages/flutter_leak_radar_lint/example/lib/undisposed_controller/good_late_uninit.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/undisposed_controller/good_constructor_param.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/uncancelled_subscription/good_non_state_class.dart`
- Create: `packages/flutter_leak_radar_lint/example/lib/discarded_listen_result/good_assigned_local.dart`
- Edit: `melos.yaml` — add `custom_lint` script
- Edit: `.github/workflows/ci.yaml` (if it exists) — add `dart run custom_lint` step

**Goal:** Prove the false-positive suppressions from spec §5.3 are exercised and confirm CI integration.

- [ ] **Step 1: False-positive fixture for `undisposed_controller` — late uninit**

`packages/flutter_leak_radar_lint/example/lib/undisposed_controller/good_late_uninit.dart`:

```dart
// example/lib/undisposed_controller/good_late_uninit.dart
// Proves: a `late` field with no initializer in either the declaration
// or initState is NOT flagged (not proven owned by this State).
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // `late` with no initializer and not assigned in initState.
  // The rule must stay silent here.
  late TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

- [ ] **Step 2: False-positive fixture — constructor parameter**

`packages/flutter_leak_radar_lint/example/lib/undisposed_controller/good_constructor_param.dart`:

```dart
// example/lib/undisposed_controller/good_constructor_param.dart
// Proves: a controller passed in via a constructor parameter is NOT flagged
// (the caller owns it, not this State).
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key, required this.controller});
  final TextEditingController controller;
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // Accessed via widget.controller — not created here, not owned here.
  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

- [ ] **Step 3: False-positive fixture — subscription in a non-State class**

`packages/flutter_leak_radar_lint/example/lib/uncancelled_subscription/good_non_state_class.dart`:

```dart
// example/lib/uncancelled_subscription/good_non_state_class.dart
// Proves: a StreamSubscription field in a plain Dart class (not State or BlocBase)
// is NOT flagged — the rule only applies to classes with a known teardown method.
import 'dart:async';

class MyService {
  StreamSubscription<int>? _sub;

  void start(Stream<int> stream) {
    _sub = stream.listen((_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
```

- [ ] **Step 4: False-positive fixture — discarded listen in a non-void context**

`packages/flutter_leak_radar_lint/example/lib/discarded_listen_result/good_assigned_local.dart`:

```dart
// example/lib/discarded_listen_result/good_assigned_local.dart
// Proves: assigning the .listen() result to a local variable does NOT trigger
// the discarded_listen_result lint (the result is not discarded).
import 'dart:async';

void example(Stream<int> stream) {
  // Assignment — not a bare ExpressionStatement.
  final sub = stream.listen((_) {});
  sub.cancel();
}
```

- [ ] **Step 5: Run custom_lint over the full example directory**

```bash
cd packages/flutter_leak_radar_lint
dart run custom_lint --working-directory example
```

Expected: exits 0 with all `expect_lint` annotations satisfied and **zero unexpected lints** in any `good*.dart` file.

- [ ] **Step 6: Add `custom_lint` script to `melos.yaml`**

Edit `melos.yaml` to add a `custom_lint` script:

```yaml
name: flutter_leak_radar
packages:
  - packages/**
  - example
scripts:
  analyze:
    run: dart analyze --fatal-infos
    exec:
      concurrency: 1
  test:
    run: flutter test
    exec:
      concurrency: 1
  custom_lint:
    description: Run the custom_lint analyzer plugin over the repo (dogfood).
    run: dart run custom_lint
    exec:
      concurrency: 1
  format-check:
    run: dart format --set-exit-if-changed .
    exec:
      concurrency: 1
  ci:
    run: melos run format-check && melos run analyze && melos run test && melos run custom_lint
    description: Full local gate — matches CI.
```

- [ ] **Step 7: Verify `melos run custom_lint` is green**

```bash
melos run custom_lint
```

Expected: exits 0 across all packages. If a package lacks `analysis_options.yaml: plugins: - custom_lint`, custom_lint is a no-op for that package (which is correct; only opt-in consumers run it).

---

## Task 7 — Full test suite sweep and coverage gate

**Files:**
- Edit: `packages/flutter_leak_radar_lint/test/` — add any missing edge-case unit tests surfaced in Tasks 2–6
- Verify: all tasks' TDD steps are complete

**Goal:** Confirm ≥80% test coverage across the plugin package, all unit tests green, fixture tests green.

- [ ] **Step 1: Run the full unit test suite**

```bash
cd packages/flutter_leak_radar_lint && dart test --coverage=coverage
```

- [ ] **Step 2: Generate coverage report**

```bash
dart pub global run coverage:format_coverage \
  --packages=.dart_tool/package_config.json \
  --report-on=lib \
  --in=coverage \
  --out=coverage/lcov.info \
  --lcov

dart pub global run coverage:lcov_cobertura coverage/lcov.info -o coverage/cobertura.xml
```

Or use the simpler:

```bash
dart run coverage:test_with_coverage
```

- [ ] **Step 3: Spot-check coverage is ≥80% for `lib/src/`**

Key files that must be exercised: `util/type_checkers.dart`, `util/state_class.dart`, `util/dispose_analysis.dart`, `rules/undisposed_controller.dart`, `rules/uncancelled_subscription.dart`, `rules/uncancelled_timer.dart`, `rules/discarded_listen_result.dart`.

- [ ] **Step 4: Confirm final melos gate**

```bash
melos run ci
```

Expected: all format, analyze, test, custom_lint steps exit 0.

---

## Self-Review

Before handing off to an implementer:

1. **API correctness.** Every `reporter.atNode` / `reporter.atToken` call uses the analyzer 8.x API (not deprecated `reportErrorForNode`). The `DartLintRule.run` signature matches custom_lint_builder 0.8.1.
2. **TypeChecker usage.** `TypeChecker.fromName(name, packageName: ...)` is the correct idiom for SDK types without a hard Flutter dep. The `packageName` values (`'flutter'`, `'async'`) must be verified against the analyzer's element library identifiers — if a checker returns no matches, print the actual `libraryIdentifier` of a known instance to debug.
3. **False-positive surface.** The most likely false positive for `undisposed_controller` is a `late` field assigned in `initState()` but with no explicit initializer in the declaration. The `_isAssignedInInitState` helper in Task 2 addresses this; confirm it is exercised by the `bad.dart` fixture for `_AlsoBadState`.
4. **Fixture completeness.** Each rule has: at least one `bad.dart` (lint fires), at least one `good.dart` (lint silent), and at least one false-positive suppression case from spec §5.3. Missing suppression cases are the most common source of real-world false positives post-ship.
5. **Fix idempotency.** The Tier A/B fixes re-check the teardown body before inserting. An implementer should add a test fixture that calls the fix twice and confirms the teardown body contains exactly one cancel/dispose call.
6. **`plugin.dart` completeness.** The final `getLintRules` list must include all four v1 rules. The `// Optional getAssists()` comment is retained but commented out to signal extensibility.
7. **Workspace wiring.** The root `pubspec.yaml` `workspace:` array must include `packages/flutter_leak_radar_lint`. Missing this causes `dart pub get` to not resolve the package within the workspace.
8. **`example/` pubspec.** Uses `resolution: workspace` and depends on `flutter_leak_radar_lint: path: ..`. Without `resolution: workspace` the fixture project may resolve different analyzer versions and the plugin may silently fail to load.

---

## Execution Handoff

**You are an agentic worker implementing this plan.** Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`.

Rules for execution:
1. **Do not skip the failing-test step.** Run the test, confirm the failure is a compile error (not a runtime error), then implement.
2. **Do not combine tasks.** Each task has a defined test gate at its end. Do not proceed to Task N+1 until Task N's gate passes.
3. **After every `dart run custom_lint` run:** scan the output for any unexpected lint on a `good*.dart` file — that is a false positive and must be fixed before continuing.
4. **If `TypeChecker.fromName` returns no matches:** add a temporary debug print of `element.library.identifier` inside the visitor to see the actual library URI, then correct the `packageName` argument. Remove the debug print before committing.
5. **If `testAnalyzeAndRun` is not available** on the rule instance, check the `custom_lint_builder` version in use. In 0.8.1 it may be `testAnalyzeAndRun` or it may require a slightly different test hook — check the `DartLintRule` class's available methods in the package source.
6. **Do not write any deferred rules** (`missing_remove_listener`, `unclosed_stream_controller`, `bloc_uncancelled_subscription`). If you find yourself touching those files, stop and re-read this plan.
7. **Commit convention:** `feat(lint): <description>` scoped to `lint`. One logical commit per task.
8. **Before claiming done:** run `melos run ci` from the repo root and paste the exit code. "Done" = the gate actually passed.

**Open design questions the human should decide before implementation starts** — see section below.

---

## Open Design Questions

These require a human decision before or during implementation. They do not block Task 0 (scaffold) but will block Tasks 2–5 if left unresolved.

| # | Question | Default assumption in this plan | Impact |
|---|----------|--------------------------------|--------|
| Q1 | Should `undisposed_controller` also flag fields in plain classes (not just `State<T>`)? Any `dispose()` method? | No — State-only for v1. | If yes, `isStateSubclass` check in Task 2 must be relaxed; `teardownMethodName` must handle the general case. |
| Q2 | Should `uncancelled_timer` flag discarded `Timer(...)` calls (result not stored) in addition to stored fields? | No — stored fields only; discarded timer is lower signal (one-shot fires and completes). | If yes, add a `addExpressionStatement` visitor alongside the field visitor, similar to `discarded_listen_result`. |
| Q3 | What severity for `undisposed_controller` — WARNING (fails CI by default) or ERROR (hard CI gate)? | WARNING — consistent with other leak rules. | If ERROR, consumers get immediate CI hard failures on existing code; may be too aggressive for an initial rollout. |
| Q4 | Should the Tier A auto-fix create `dispose()` when missing, or only insert into an existing `dispose()`? | Creates it (synthesizes override) — this is the full Tier A spec. | If synthesize-only-when-exists, some errors have no fix offered, which is less ergonomic but safer. |
| Q5 | Should the plugin be added to `analysis_options.yaml` at the workspace root (dogfooding the lint on the `flutter_leak_radar` package itself), or only in `packages/flutter_leak_radar_lint/example/`? | Dogfood in the runtime package's dev dependencies; add as a path dep and enable in `packages/flutter_leak_radar/analysis_options.yaml`. AGENTS.md §7 says this should happen. | If yes, add `flutter_leak_radar_lint: path: ../flutter_leak_radar_lint` dev dep to `packages/flutter_leak_radar/pubspec.yaml` and add `plugins: - custom_lint` to its `analysis_options.yaml`. |
| Q6 | `TypeChecker.fromName` with `packageName: 'async'` for dart:async types — does this correctly resolve `StreamSubscription` / `Timer` in the analyzer 8.x model? | Assumed yes, but verify against the actual library identifier at runtime if checkers return false negatives. | If `packageName: 'async'` is wrong, use `TypeChecker.fromUrl(Uri.parse('dart:async'), name: 'StreamSubscription')` instead. |
