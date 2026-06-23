# Lint Rules Implementation Report

**Branch:** `feat/lint-rules`
**Package:** `packages/flutter_leak_radar_lint`
**Status:** DONE — all 3 rules shipped.

## Summary

Three new `custom_lint` rules were added to the `flutter_leak_radar_lint` plugin,
mirroring the structure of the existing four rules and reusing the shared
`util/` helpers (`type_checkers.dart`, `state_class.dart`, `dispose_analysis.dart`).
All three are registered in `getLintRules()` and `plugin.dart`. Severity WARNING
for all three.

| # | Rule | Auto-fix | Outcome |
|---|------|----------|---------|
| 1 | `unclosed_stream_controller` | Yes (Tier A, sync teardown) | Shipped |
| 2 | `missing_remove_listener` | No (Tier C, message-only) | Shipped |
| 3 | `bloc_uncancelled_subscription` | No (message-only) | Shipped |

## Rule 1 — `unclosed_stream_controller`

A `StreamController` field created/owned in a `State`/`BlocBase` class that is
never `.close()`-ed in the teardown method. Mirrors `uncancelled_subscription`
exactly with `teardownCall: 'close'`. Auto-fix inserts `<field>.close();` into
the teardown (before `super.dispose()`), synthesising a `dispose()` override if
absent. A `close()` override is **never** synthesised (its async return type
makes trivial synthesis incorrect — identical guard to the existing rules).

New helper added: `kStreamControllerChecker` in `type_checkers.dart`.

## Rule 2 — `missing_remove_listener` (conservative)

`<listenable>.addListener(cb)` with no matching `<listenable>.removeListener(cb)`
in any teardown method (`dispose`/`deactivate` for State, `close` for Bloc).

**Conservatism (false negatives accepted, false positives forbidden):**
- Only fires when the receiver is a bare field/identifier (`SimpleIdentifier`)
  whose static type is assignable to Flutter's `Listenable`/`ChangeNotifier`/
  `Animation` — unrelated user-defined `addListener` methods are ignored.
- Only pairs **tear-offs / named references** (`_onChange`, `widget.onChange`).
  Inline closures (`() {}`) have no referenceable identity and are **never
  flagged** — documented as a deliberate false negative.
- Callback identity is matched by exact source text (no alias resolution).
- **Suppressed** when the receiver is itself a disposable controller already
  covered by `undisposed_controller` (e.g. `AnimationController`) — `dispose()`
  drops its listeners, so flagging `removeListener` would double-report.

New helpers added to `dispose_analysis.dart`: `collectPairableAddListeners()`,
`hasMatchingRemoveListener()`. New type checkers: `kListenableChecker`,
`kChangeNotifierChecker`, `kAnimationChecker`, `kListenableTypes`.

## Rule 3 — `bloc_uncancelled_subscription`

A `package:bloc` `BlocBase` (Bloc/Cubit) subclass that calls `.listen(...)` in
its **constructor** without cancelling in `close()`.

- Gated on the consumer depending on `package:bloc` via `isBlocBaseSubclass`
  (resolves against `bloc`'s `BlocBase`; if bloc is unresolvable, no class
  matches and the rule is silent).
- `emit.forEach(...)` / `emit.onEach(...)` are bloc-managed and **never flagged**
  (they are not `.listen` calls; any `.listen` whose receiver is `emit` is also
  skipped defensively).
- Scope-limited to `.listen` calls **textually inside the constructor**, which
  avoids double-reporting with `uncancelled_subscription` (which already covers
  BlocBase fields).
- Field-assigned case clears only if `.cancel()`'d in `close()`. Discarded bare
  `.listen(...)` statement always flags. Local vars / returns / awaits / args
  are conservatively ignored (no field to cancel ⇒ out of scope, avoids FPs).

## TDD / FP-guard fixtures

Each rule has a `bad.dart` (SHOULD-flag, `expect_lint` annotated) and a
`good.dart` (zero lints) under `test/fixtures/<rule>/`, plus example fixtures
under `example/lib/<rule>/`.

**FP-guard cases (good.dart) per rule:**
- `unclosed_stream_controller`: closed top-level, closed in if-block, closed in
  try-block, cascade `..close()`, local variable, field-formal `this._x`,
  named-param injection, plain non-State/Bloc class.
- `missing_remove_listener`: paired removeListener, removeListener in if-block,
  removeListener in `deactivate()`, inline-closure (skipped), AnimationController
  (suppressed/double-report guard), plain Dart class (no teardown), unrelated
  user-defined `addListener`.
- `bloc_uncancelled_subscription`: cancelled in `close()`, cancelled in if-block,
  `emit.forEach`, `emit.onEach`, `.listen` in a non-constructor method (out of
  scope), `.listen` in a non-bloc class.

## Verification

- **`dart test`** (in `packages/flutter_leak_radar_lint`): **28 passed**
  (21 baseline + 7 new). Exact diagnostic counts asserted (e.g. bad.dart yields
  exactly 2/2/3 lints respectively).
- **`dart analyze packages/flutter_leak_radar_lint`**: **No issues found.**
- **`dart format --set-exit-if-changed`**: clean (0 changed).
- **`dart run custom_lint` (example)**: exits **0** with no reported lints.

### KNOWN ENVIRONMENT CAVEAT (pre-existing, not introduced by this work)

`dart run custom_lint` against `example/` is **vacuous in this workspace**: the
example is a pub-workspace sub-package with no local
`.dart_tool/package_config.json`, and custom_lint 0.8.1 fails to bootstrap the
plugin runner from it. Verified by removing an `expect_lint` from a **pre-existing**
baseline fixture (e.g. `uncancelled_subscription/bad.dart`) and from a fresh
blatant `undisposed_controller` probe file — neither was reported, and the run
still exited 0. This affects **all** rules equally and was true before these
changes. The dogfood path the repo documents is `melos run custom_lint`
(per-package), which was not runnable here because `melos` is not on PATH in
this environment.

**Real validation is the unit-test layer** (`testAnalyzeAndRun`), which genuinely
resolves each fixture and runs each rule's `run()` — all 28 pass, including every
FP-guard `good.dart` asserting zero diagnostics. The example fixtures are written
and `expect_lint`-annotated so they will gate correctly once the workspace
custom_lint bootstrap is fixed (out of scope for this task).

## Files

New rules:
- `lib/src/rules/unclosed_stream_controller.dart`
- `lib/src/rules/missing_remove_listener.dart`
- `lib/src/rules/bloc_uncancelled_subscription.dart`

Shared util additions:
- `lib/src/util/type_checkers.dart` (StreamController, Listenable family, BlocBase)
- `lib/src/util/dispose_analysis.dart` (addListener/removeListener pairing helpers)

Registration: `lib/src/plugin.dart`.
Example dep: `example/pubspec.yaml` (added `bloc: ^9.2.1`).
Tests + fixtures: `test/<rule>_test.dart`, `test/fixtures/<rule>/`,
`example/lib/<rule>/`.
