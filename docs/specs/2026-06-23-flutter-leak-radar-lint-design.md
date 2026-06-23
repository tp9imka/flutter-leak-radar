# flutter_leak_radar_lint — Design Spec

`packages/flutter_leak_radar_lint` is sub-project 2 of the **flutter-leak-radar** monorepo: a `custom_lint`-based analyzer plugin that flags Flutter/Dart memory-leak patterns at edit/compile time. It is developed in parallel with the runtime detection package (sub-project 1) and shares its taxonomy of leak classes.

Targets: **Dart 3.10**, **analyzer ^8.0.0**, **custom_lint / custom_lint_builder 0.8.1** (current as of June 2026).

> **API-version note (load-bearing).** With analyzer 8.x the older `reporter.reportErrorForNode(...)` is deprecated. Use the location-named reporters: `reporter.atNode(node, code)`, `reporter.atToken(...)`, `reporter.atOffset(...)`. The dual `Element2` model was collapsed back to `Element` in analyzer 8.x — write against `Element`, not `Element2`. Most blog examples (incl. charlescyt) still show analyzer 6.x (`reportErrorForNode`, `staticElement`); treat them as structurally correct but update the reporter/element calls.

---

## 1. Goals / Non-goals

### Goals

- Catch the **common, statically-detectable** Flutter/Dart leak patterns at authoring time, before the app runs: undisposed `State` controllers, uncancelled `StreamSubscription`s, uncancelled `Timer`s, `addListener` without `removeListener`, unclosed `StreamController`s, BLoC/Cubit subscriptions without `close()`, and discarded `.listen()` results.
- Provide **safe, high-confidence quick-fixes** where a single deterministic edit resolves the leak (primarily: insert the teardown call into `dispose()`/`close()`, creating the override if needed).
- Keep the analysis **fast and pure-Dart** — intra-class, single-file flow reasoning only. No whole-program escape analysis, no `flutter` hard dependency.
- Ship as a clean monorepo package with one rule per file, shared AST/element helpers in `util/`, and a fixture-based test suite that doubles as living documentation.
- Make the plugin **CI-gateable** (`dart run custom_lint` exits non-zero on WARNING/ERROR) and **IDE-live** (VS Code / IntelliJ surface diagnostics with no extra config).

### Non-goals

- **No runtime detection.** Heap inspection, retain-path analysis, and leak confirmation belong to the runtime package. The lint cannot prove a leak occurs; it flags shapes that are leak-prone.
- **No cross-file ownership tracking.** If a controller is created in one class and disposed in another, the lint will not follow it. This is a deliberate scope boundary (see §7) and a documented false-positive source.
- **No data-flow / alias analysis.** We pair teardown calls by syntactic receiver + callback identity, not by full alias resolution.
- **No autofix where the correct edit is ambiguous** (e.g. removing an inline-closure listener, cancelling a discarded `Timer`). Those rules are message-only.
- **Not a replacement for the runtime package.** The two are complementary layers; neither subsumes the other.

---

## 2. Relationship to the runtime package

The two sub-projects target the **same taxonomy of leak classes from opposite ends of the lifecycle**. They are parallel defenses, not redundant ones.

| Leak class | Runtime package (sub-project 1) DETECTS | Lint plugin (sub-project 2) PREVENTS |
|---|---|---|
| Undisposed `State` controllers | Observes the object surviving past `State` disposal on the heap | Flags the missing `dispose()` call at edit time |
| Uncancelled `StreamSubscription` | Detects the subscription kept alive after scope teardown | Flags the missing `.cancel()` in `dispose()`/`close()` |
| Uncancelled `Timer` | Detects the live timer retaining its closure | Flags the discarded / never-cancelled `Timer` |
| `addListener` w/o `removeListener` | Detects the listenable retaining the listener closure | Flags the unmatched `addListener` |
| Unclosed `StreamController` | Detects the controller (and its buffer) surviving | Flags the missing `.close()` |
| BLoC/Cubit subscription w/o `close()` | Detects the BLoC retained via its open subscription | Flags the subscription not torn down in `close()` |

**Design contract between the two packages:**

- **Shared vocabulary.** Lint codes (snake_case) map 1:1 to runtime leak-class identifiers so a developer sees the *same name* whether the issue surfaces in their editor or in a runtime report. Keep the identifier list in a single shared doc/source of truth.
- **Complementary coverage.** The lint catches the *typical* shape cheaply and early; the runtime package catches the *atypical* shapes the static analysis deliberately cannot see (cross-file ownership, dynamic dispatch, collections of controllers). A pattern the lint suppresses to avoid a false positive is exactly the kind of thing the runtime layer is there to backstop.
- **Independent release cadence.** The lint plugin and runtime package version independently; the only coupling is the shared identifier vocabulary. No code dependency in either direction.

---

## 3. Plugin architecture

### 3.1 Directory layout

```text
packages/flutter_leak_radar_lint/
├── pubspec.yaml
├── analysis_options.yaml            # lints for the plugin's OWN source
├── lib/
│   ├── flutter_leak_radar_lint.dart # exports createPlugin()
│   └── src/
│       ├── plugin.dart              # PluginBase + getLintRules()
│       ├── util/
│       │   ├── type_checkers.dart   # TypeChecker constants (Flutter SDK types)
│       │   ├── dispose_analysis.dart# shared "is X torn down in dispose()/close()?" logic
│       │   └── state_class.dart     # helpers: is this a State<T>/BlocBase subclass?
│       └── rules/
│           ├── undisposed_controller.dart
│           ├── uncancelled_subscription.dart
│           ├── uncancelled_timer.dart
│           ├── missing_remove_listener.dart
│           ├── unclosed_stream_controller.dart
│           ├── bloc_uncancelled_subscription.dart
│           └── discarded_listen_result.dart
├── example/                         # consumer test project (also CI fixture)
│   ├── pubspec.yaml
│   ├── analysis_options.yaml
│   └── lib/<rule_name>/{good,bad}.dart   # fixtures with // expect_lint:
└── test/
    └── *_test.dart                  # programmatic rule tests
```

One rule per file (each ~80–200 lines), shared AST/element logic in `util/`. Matches the file-organization rule: many small, cohesive files organized by feature.

### 3.2 `pubspec.yaml` (the plugin package)

```yaml
name: flutter_leak_radar_lint
description: Lints that catch common Flutter/Dart memory-leak patterns.
version: 0.1.0
publish_to: none            # internal monorepo package; drop if publishing

environment:
  sdk: ^3.10.0

dependencies:
  analyzer: ^8.0.0
  analyzer_plugin: ^0.13.0  # transitively required; pin to what custom_lint resolves
  custom_lint_builder: ^0.8.1

dev_dependencies:
  custom_lint: ^0.8.1
  test: ^1.25.0
```

`custom_lint_builder` is the authoring dependency; `custom_lint` is dev-only (used to run/test). Do **not** add `flutter` as a hard dependency — resolve Flutter SDK types by their library URI via `TypeChecker` so the analyzer plugin stays pure-Dart and fast.

### 3.3 Entry point — `lib/flutter_leak_radar_lint.dart`

```dart
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'src/plugin.dart';

// custom_lint discovers this exact top-level function by name.
PluginBase createPlugin() => FlutterLeakRadarPlugin();
```

The runner reflects on the package and calls the top-level `createPlugin()`. Name and signature are fixed.

### 3.4 Plugin class — `lib/src/plugin.dart`

```dart
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'rules/undisposed_controller.dart';
import 'rules/uncancelled_subscription.dart';
import 'rules/uncancelled_timer.dart';
import 'rules/missing_remove_listener.dart';
import 'rules/unclosed_stream_controller.dart';
import 'rules/bloc_uncancelled_subscription.dart';
import 'rules/discarded_listen_result.dart';

class FlutterLeakRadarPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
        UndisposedController(),
        UncancelledSubscription(),
        UncancelledTimer(),
        MissingRemoveListener(),
        UnclosedStreamController(),
        BlocUncancelledSubscription(),
        DiscardedListenResult(),
      ];

  // Optional — only if you ship standalone assists (refactors not tied to a lint).
  // @override
  // List<Assist> getAssists() => const [];
}
```

`getLintRules` receives `CustomLintConfigs` (the parsed `custom_lint:` block from the consumer's `analysis_options.yaml`). Per-rule options (thresholds, allow-lists) can be read off it. custom_lint handles enable/disable from config automatically based on each rule's `code.name`, so the full list is normally returned unconditionally.

### 3.5 A lint rule — shape (`DartLintRule`)

```dart
import 'package:analyzer/error/error.dart';      // ErrorSeverity, AnalysisError
import 'package:analyzer/error/listener.dart';   // ErrorReporter
import 'package:custom_lint_builder/custom_lint_builder.dart';

class UndisposedController extends DartLintRule {
  const UndisposedController() : super(code: _code);

  static const _code = LintCode(
    name: 'undisposed_controller',
    problemMessage:
        "This controller is created in the State but never disposed in dispose().",
    correctionMessage: "Call '{0}.dispose()' inside the State's dispose() method.",
    errorSeverity: ErrorSeverity.WARNING,   // defaults to INFO if omitted
    url: 'https://internal.docs/leak-radar/undisposed_controller',
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addFieldDeclaration((node) {
      // ... analysis ...
      // analyzer 8.x: use atNode (NOT reportErrorForNode)
      // reporter.atNode(offendingNode, _code, arguments: [fieldName]);
    });
  }

  @override
  List<Fix> getFixes() => [AddDisposeCall()];
}
```

Notes that matter for 0.8.1 / analyzer 8:

- `run()` signature is `(CustomLintResolver, ErrorReporter, CustomLintContext)`.
- Register **syntactic visitors** on `context.registry` (`addFieldDeclaration`, `addClassDeclaration`, `addMethodInvocation`, `addVariableDeclarationStatement`, etc.). The visitor fires once per matching node across the resolved unit.
- Reporting: `reporter.atNode(node, code, arguments: [...])`. `arguments` fills `{0}`, `{1}` placeholders in the messages.
- `code.name` is the snake_case identifier consumers use to enable/disable/ignore (`// ignore: undisposed_controller`).
- `errorSeverity`: `ERROR` (fails `dart run custom_lint` / CI hard), `WARNING` (shows, fails CI by default exit code), `INFO` (informational). Leak rules below are mostly `WARNING`.

### 3.6 A quick-fix — shape (`DartFix`)

```dart
class AddDisposeCall extends DartFix {
  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError analysisError,         // the lint this fix targets
    List<AnalysisError> others,          // other lints in the same file (batch fixes)
  ) {
    context.registry.addMethodDeclaration((node) {
      // Only act on the node overlapping the reported error.
      if (!node.sourceRange.intersects(analysisError.sourceRange)) return;

      final changeBuilder = reporter.createChangeBuilder(
        message: "Dispose 'controller' in dispose()",
        priority: 80,
      );
      changeBuilder.addDartFileEdit((builder) {
        builder.addSimpleInsertion(offset, '\n    controller.dispose();');
        // builder.importLibraryElement(uri) // if the fix needs new imports
      });
    });
  }
}
```

`getFixes()` on the rule returns the fixes; each `DartFix.run` is handed the specific `AnalysisError` plus siblings (so it can power "fix all"). Bind the fix to the right node via `sourceRange.intersects(analysisError.sourceRange)`. Mutations go through `ChangeBuilder` (`addSimpleInsertion`, `addSimpleReplacement`, `addReplacement`, `importLibraryElement`) — never mutate source strings yourself.

---

## 4. Consumer integration

In the **app/package that consumes** the lints:

1. Add dev dependencies:

```yaml
dev_dependencies:
  custom_lint: ^0.8.1
  flutter_leak_radar_lint:
    path: ../packages/flutter_leak_radar_lint   # or hosted/git
```

2. Enable the plugin in `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint

# Optional: per-rule control
custom_lint:
  rules:
    - undisposed_controller            # enabled
    - discarded_listen_result: false   # disabled
    # enable_all_lint_rules: false     # then list only the ones you want
```

3. Run it:

```bash
dart run custom_lint            # pure Dart packages
flutter pub run custom_lint     # Flutter packages (or: dart run custom_lint within the package)
```

The IDE (VS Code / IntelliJ with the Dart plugin) surfaces the lints live once the analyzer plugin loads — no extra IDE config beyond the `plugins: - custom_lint` line. Per-line suppression uses the standard `// ignore: <code_name>` and `// ignore_for_file: <code_name>`.

### CI

`dart run custom_lint` exits non-zero when any lint of severity WARNING/ERROR is found, so CI is just:

```yaml
# GitHub Actions step
- run: dart pub get
- run: dart run custom_lint        # in each package that enables it
```

Gotchas worth encoding in CI docs:

- Run `dart pub get` first; the plugin is compiled on first run and cached, so the first CI run is slower.
- Run it **per package** (custom_lint is not transitively run across a workspace automatically). For a monorepo, iterate packages (e.g. `melos exec -- dart run custom_lint`).
- Keep analyzer versions aligned across packages — a mismatch between the app's `analyzer` and the plugin's `analyzer ^8.0.0` is the most common "plugin failed to start" cause.

---

## 5. The rule set

### 5.1 Shared infrastructure (`util/`)

Most rules reuse:

- **`TypeChecker` constants** for the SDK types: `AnimationController`, `TextEditingController`, `ScrollController`, `TabController`, `PageController`, `FocusNode` (package:flutter/widgets, material), `StreamSubscription`, `StreamController`, `Timer` (dart:async), `State`, `ChangeNotifier`, `Listenable`, `Animation`, `Bloc`/`Cubit`/`BlocBase` (package:bloc). Use `TypeChecker.isAssignableFrom` / `isSuperTypeOf` against the field/expression static type.
- **`disposedInTeardown(ClassDeclaration cls, target)`** — finds the teardown method (`dispose()` for `State`, `close()` for `Bloc`/`Cubit`) and scans its body for a `<target>.dispose()` / `.cancel()` / `.close()` / `removeListener(...)` invocation on the target. This single "is the teardown called in the teardown method?" helper backs rules 1, 2, 4, 5, 6.
- **`state_class.dart`** — `isStateSubclass` / `isBlocBaseSubclass` checks plus the corresponding teardown-method name.

This is intra-class, single-file flow reasoning. It is deliberately **not** whole-program escape analysis — keeping it local keeps the plugin fast and the false-positive surface understandable.

### 5.2 Rule table

| # | Code (snake_case) | Flags (AST shape) | Severity | Auto-fix? |
|---|---|---|---|---|
| 1 | `undisposed_controller` | `FieldDeclaration` in a `State<T>` subclass whose field type is assignable to {AnimationController, TextEditingController, ScrollController, TabController, PageController, FocusNode}, assigned (initializer or `initState`), with no `<field>.dispose()` in `dispose()`. | WARNING | **Yes (high confidence).** Insert `<field>.dispose();` into `dispose()`, creating the override (ordered before `super.dispose()`) if absent. |
| 2 | `uncancelled_subscription` | Field/local of type assignable to `StreamSubscription` assigned from a `.listen(...)` invocation, with no `<sub>.cancel()` in `dispose()`/`close()` (fields) or before scope exit (locals). | WARNING | **Partial.** Field case: insert `<sub>.cancel();` into teardown. Local case: message-only nudge (it usually shouldn't be a field at all). |
| 3 | `uncancelled_timer` | `Timer(...)` / `Timer.periodic(...)` whose result is not assigned to a field/var later `.cancel()`-ed, or assigned to a field with no `.cancel()` in teardown. `Timer.periodic` weighted higher. | WARNING (periodic) / INFO (discarded one-shot) | **Partial.** If stored in a field: insert `<field>?.cancel();` in teardown. If discarded entirely: message-only (no safe single edit). |
| 4 | `missing_remove_listener` | `x.addListener(cb)` (receiver assignable to `Listenable`/`ChangeNotifier`/`Animation`) in a class, with no matching `x.removeListener(cb)` reachable in `dispose()`/`deactivate()`. Paired by receiver + callback identity. | WARNING | **No.** Removing a listener needs the exact same callback reference; inline closures have no referenceable target. Message + doc only. |
| 5 | `unclosed_stream_controller` | `FieldDeclaration`/local of type assignable to `StreamController` that is created/owned and has no `<field>.close()` in `dispose()`/`close()` (fields) or before scope exit (locals). | WARNING | **Yes (field case).** Insert `<field>.close();` into teardown, creating the override if absent. Local case: message-only. |
| 6 | `bloc_uncancelled_subscription` | Inside a `Bloc`/`Cubit`/`BlocBase` subclass: a `StreamSubscription` field assigned from `.listen(...)` (or a `.listen(...)` whose result is discarded) with no `<sub>.cancel()` in the overridden `close()`. | WARNING | **Partial.** Field case: insert `<sub>.cancel();` into `close()` (creating the override, ordered before `super.close()`). Discarded case: message-only. |
| 7 | `discarded_listen_result` | A `MethodInvocation` named `listen` (receiver assignable to `Stream`) whose returned `StreamSubscription` is discarded — i.e. the invocation is an `ExpressionStatement` not assigned/awaited/returned. | WARNING | **No (not safe automatically).** The fix is to capture the subscription in a field and cancel it in teardown — a multi-edit refactor with naming decisions. Message + doc only. |

### 5.3 Per-rule false-positive notes

**1 — `undisposed_controller`**
- Field disposed via a loop/collection (`for (final c in _controllers) c.dispose()`).
- Disposed in a helper method that `dispose()` calls (the helper scan should follow one level of intra-class call).
- Ownership transferred out (returned, or passed to a parent that disposes it).
- `late` field never initialized → not owned by this `State`.
- Controller passed in via constructor (not created here → not owned). Suppress when the field is assigned from a constructor parameter.

**2 — `uncancelled_subscription`**
- Cancelled inside a callback, or stored in a `List<StreamSubscription>` cancelled in a loop.
- Auto-cancelling / single-event streams (`first`, `cancelOnError`).
- Cancellation in a method other than the teardown method.
- `await for` style — not applicable (no subscription object).

**3 — `uncancelled_timer`**
- One-shot `Timer` that legitimately fires once and self-completes (hence INFO, not WARNING).
- Timer cancelled inside a callback.
- Timer stored in a collection.
- `Timer.run` / microtask scheduling (not retained).

**4 — `missing_remove_listener`**
- The listenable is itself an owned, disposed controller → `removeListener` is redundant and rule 1 already covers it; **suppress here** to avoid double-reporting.
- Anonymous closure passed → callback identity can't be matched; **don't report** rather than emit a false positive.
- Listener intentionally lifetime-of-app (e.g. on a singleton/global listenable).

**5 — `unclosed_stream_controller`**
- Controller closed inside a callback or a helper.
- Broadcast controller intentionally app-lifetime.
- Controller's `stream` ownership transferred out (exposed and closed by the consumer).
- Controller received via constructor (not owned here).

**6 — `bloc_uncancelled_subscription`**
- Subscription managed via `emit.forEach` / `emit.onEach` (bloc's own lifecycle-bound helpers) → not a manual subscription; **don't report**.
- Subscription cancelled in a method other than `close()`.
- Subscription stored in a collection cancelled in a loop.

**7 — `discarded_listen_result`**
- Fire-and-forget on a stream that's known-finite/short-lived (rare; prefer suppression via `// ignore`).
- `.listen(...)` whose subscription is intentionally app-lifetime (global event bus). Documented as the canonical `// ignore` case.

---

## 6. Quick-fix design

Three fix tiers, mapped to the table above:

### Tier A — high-confidence single-edit (rules 1, 5; field cases of 2, 3, 6)

The canonical fix: **insert the teardown call into the teardown method.**

- **Locate or create the teardown method.** For `State`, that's `dispose()`; for `Bloc`/`Cubit`, `close()`. If the override is absent, the fix synthesizes it:
  - `State.dispose()`: place teardown calls **before** `super.dispose()`.
  - `Bloc/Cubit.close()`: place `.cancel()` calls **before** `return super.close()`.
- **Insert the call** (`addSimpleInsertion`) with correct indentation, in declaration order if multiple fields are involved.
- **Idempotency:** the fix must not duplicate an existing call (re-check the body before inserting).
- All edits via `ChangeBuilder.addDartFileEdit`; never string-splice.

### Tier B — partial / contextual (local-variable cases of 2, 3)

- Only offer the field-case insertion. For locals, the correct refactor (promote to field + cancel in teardown) involves naming and placement decisions; emit the lint with a `correctionMessage` pointing at the manual fix, no automated edit.

### Tier C — message-only (rules 4, 7; discarded cases of 3, 6)

- No automated edit. `correctionMessage` describes the manual remediation:
  - rule 4: "Capture the listener in a named field and call `removeListener` with the same reference in `dispose()`."
  - rule 7: "Assign the subscription to a field and cancel it in `dispose()`/`close()`."
- These rules implement `run()` for reporting but return `[]` from `getFixes()`.

### Fix correctness guardrails

- Bind every fix to its node with `node.sourceRange.intersects(analysisError.sourceRange)`.
- Use `builder.importLibraryElement(...)` if a fix needs a new import (e.g. synthesizing an `@override` annotation target); never hand-write import lines.
- Snapshot-test every fix output (§7) — a wrong autofix is worse than no autofix.

---

## 7. Testing strategy

Two complementary layers, both verified against 0.8.1.

### 7.1 Fixture / golden tests (primary, highest signal)

custom_lint ships a `// expect_lint: <code_name>` mechanism. The `example/` project depends on the plugin and enables it. In fixture files, annotate the line **above** each expected diagnostic:

```dart
// example/lib/undisposed_controller/bad.dart
class _MyState extends State<MyWidget> {
  // expect_lint: undisposed_controller
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) => const SizedBox();
}
```

`dart run custom_lint` over that project asserts that **every** `expect_lint` line is satisfied and that **no other** lints fire — a missing or extra diagnostic fails the run. Maintain paired `good.dart` (zero lints) / `bad.dart` (expects the lint) per rule. This is where false positives are caught and it doubles as living documentation + the CI gate for the plugin itself.

### 7.2 Programmatic unit tests

`DartLintRule`, `DartFix`, and `DartAssist` expose test hooks:

- `testAnalyzeAndRun(File)` → resolves the file and returns the `List<AnalysisError>` the rule produces. Assert count/offset/code/arguments.
- `testRun(...)` → lower-level run against a resolved unit.
- For fixes, `matcherNormalizedPrioritizedSourceChangeSnapshot` compares the produced `SourceChange` against a snapshot.

```dart
// test/undisposed_controller_test.dart
import 'dart:io';
import 'package:flutter_leak_radar_lint/src/rules/undisposed_controller.dart';
import 'package:test/test.dart';

void main() {
  test('flags an undisposed TextEditingController', () async {
    final errors = await const UndisposedController()
        .testAnalyzeAndRun(File('test/fixtures/undisposed_controller/bad.dart'));
    expect(errors, hasLength(1));
    expect(errors.single.errorCode.name, 'undisposed_controller');
  });

  test('does not flag a disposed controller', () async {
    final errors = await const UndisposedController()
        .testAnalyzeAndRun(File('test/fixtures/undisposed_controller/good.dart'));
    expect(errors, isEmpty);
  });
}
```

### 7.3 Coverage policy

- Fixture tests for **breadth** (cheap to add cases, catch FPs); programmatic tests for **precision** (offset/argument/fix-output assertions).
- Every false-positive note in §5.3 gets a `good.dart` case proving the rule stays silent — these are first-class tests.
- Every Tier A/B fix gets a snapshot test of its `SourceChange`.
- Target ≥80% coverage with the false-positive cases counted.

---

## 8. Milestones

**M0 — Scaffold (week 1).** Package skeleton, `pubspec.yaml`, `createPlugin()` entry point, empty `FlutterLeakRadarPlugin`, `example/` consumer project wired up, CI step running `dart run custom_lint` green on an empty rule set. Establishes the shared identifier vocabulary doc with the runtime package.

**M1 — Shared infrastructure (week 1–2).** `util/type_checkers.dart`, `util/state_class.dart`, `util/dispose_analysis.dart` (`disposedInTeardown`). Unit-tested in isolation against fixtures.

**M2 — Tier A rules + fixes (week 2–3).** `undisposed_controller` and `unclosed_stream_controller` end to end: rule, high-confidence autofix, paired good/bad fixtures, snapshot tests for fixes. Proves the full authoring → fix → test loop.

**M3 — Subscription & timer rules (week 3–4).** `uncancelled_subscription`, `uncancelled_timer`, `discarded_listen_result` (rule 7 message-only). Partial fixes for the field cases.

**M4 — Listener & BLoC rules (week 4–5).** `missing_remove_listener` (message-only, with the rule-1 suppression to avoid double-reporting) and `bloc_uncancelled_subscription` (partial fix into `close()`). Requires the BLoC `TypeChecker`s and the `emit.forEach`/`onEach` suppression.

**M5 — Hardening & docs (week 5–6).** Sweep every §5.3 false-positive note into a `good.dart` case; per-rule `url` docs published at the internal docs base; finalize consumer integration + monorepo CI (`melos exec`) instructions; align analyzer version across the workspace; ≥80% coverage gate.

**M6 — Consumer rollout.** Enable in one real app package behind per-rule config, tune severities/allow-lists from real findings, then widen. Reconcile lint codes against the runtime package's leak-class identifiers one final time before tagging 1.0.0.
