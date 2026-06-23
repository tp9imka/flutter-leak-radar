# flutter-leak-radar — AGENTS.md

> Contribution guide for **all** contributors — human and AI agents alike. Read this top to bottom before touching code. It encodes hard, non-negotiable rules; violating them is a defect even if the build passes.

---

## 1. Project overview

`flutter-leak-radar` is a published, open-source Flutter **monorepo** (Melos + Dart pub workspaces) targeting **Dart 3.10 / Flutter 3.38**. It ships two independent packages plus a demo app:

- An **on-device runtime leak detector** that introspects the Dart VM heap (via the VM service) to find retained objects that should have been collected. It runs in **debug and profile only**, is **zero-config**, requires **no mandatory mixins or base classes**, and offers an **optional `track()` opt-in** for targeting specific objects.
- A **`custom_lint` analyzer plugin** that statically flags leak-prone code (undisposed controllers, listeners never removed, missing `dispose()` overrides).

The detector is a **devtool**. The most important property of a devtool is that it is invisible until you want it and harmless when you don't. Every rule below serves that property.

### Package map

```text
flutter-leak-radar/
├── pubspec.yaml                       # workspace root + melos: config (publish_to: none)
├── pubspec.lock                       # single shared lockfile for the whole workspace
├── analysis_options.yaml              # shared root lint config; packages `include:` it
├── AGENTS.md                          # this file
├── README.md                          # repo-level: what/why, links to each package's pub page
├── CONTRIBUTING.md
├── docs/
│   └── specs/                         # AUTHORITATIVE design specs — read before implementing
├── .github/workflows/ci.yaml
├── packages/
│   ├── flutter_leak_radar/            # the runtime detector (Flutter package)
│   │   ├── lib/
│   │   │   ├── flutter_leak_radar.dart   # the ONLY public entrypoint (facade)
│   │   │   └── src/                       # all internals; never imported by consumers
│   │   ├── test/
│   │   ├── example/                       # minimal runnable example (scored by pub.dev)
│   │   ├── CHANGELOG.md  README.md  LICENSE
│   │   └── pubspec.yaml                    # resolution: workspace; publish_to: pub.dev
│   └── flutter_leak_radar_lint/       # the custom_lint analyzer plugin (Dart package)
│       ├── lib/
│       │   ├── flutter_leak_radar_lint.dart
│       │   └── src/rules/                  # one rule per file
│       ├── test/
│       ├── CHANGELOG.md  README.md
│       └── pubspec.yaml
└── example/                           # shared demo Flutter app, depends on both via path:
```

> **Naming:** pub.dev package names are `snake_case`: `flutter_leak_radar` (detector) and `flutter_leak_radar_lint` (plugin). `flutter-leak-radar` is only the GitHub repo slug.

---

## 2. Golden architecture rules

These define the internal shape. They are enforced in review.

### 2.1 Clean facade, hidden internals

- Each package exposes **exactly one** public library: `lib/<package>.dart`. Everything else lives under `lib/src/` and is **never** a public import path. Consumers write `import 'package:flutter_leak_radar/flutter_leak_radar.dart';` and nothing else.
- Export with **show-lists**, never blanket `export 'src/...'`. Adding a class to `src/` must never silently widen the public API — a widened API is a semver liability.

```dart
// lib/flutter_leak_radar.dart — the entire public surface
library;

export 'src/leak_radar.dart' show LeakRadar, LeakRadarConfig;
export 'src/model/leak_report.dart' show LeakReport, LeakSummary, LeakSeverity;
// Deliberately NOT exported: VmHeapProbe, LeakAnalyzer internals,
// timers, ring buffers, vm_service plumbing, anything in src/internal/.
```

- Use `@internal` from `package:meta` on symbols that must be library-public for cross-`src` reasons but are not API.
- A thin **static facade** (`LeakRadar.install()/dispose()/snapshot()`) reads well at the call site and delegates to a hidden, fully testable singleton. `install()` must be **idempotent**.

### 2.2 The three-layer separation (mandatory)

The detector is split so that the messy, environment-dependent part is isolated from the logic:

1. **`VmHeapProbe` — the ONLY unit allowed to touch `vm_service`.**
   - All `package:vm_service` imports and VM-service-protocol calls live here and nowhere else. This is the single quarantine point for I/O, connection state, and "service unavailable" handling.
   - It exposes a narrow, plain-Dart interface (e.g. returns simple snapshots / heap records as value types) so nothing downstream knows the VM service exists.

2. **`LeakAnalyzer` — pure, synchronous, fully testable.**
   - Takes plain-Dart heap data in, produces `LeakReport`/`LeakSummary` out. **No I/O, no timers, no `vm_service`, no globals, no clock access** (inject `DateTime` / a clock if you need time). It must be unit-testable with hand-built fixtures and zero mocking of the VM.
   - All leak-detection heuristics live here. If you can't test a heuristic without a running VM, it's in the wrong layer.

3. **`LeakRadar` facade + scheduler — orchestration.**
   - Wires the probe to the analyzer on a timer, applies config, manages lifecycle, routes reports. Holds no detection logic of its own.

If a change blurs these boundaries (e.g. a `vm_service` import creeping into the analyzer), it must be rejected.

### 2.3 File organization

Organize by feature/domain under `src/`, not by type. Keep each file **200–400 lines typical, 800 max**. Extract before a file grows past that. Use `part`/`part of` only to split one cohesive library (e.g. a sealed-class family) — never as a module system.

---

## 3. Hard safety rules (non-negotiable)

This package **must never** harm the host app. These are tested invariants, not aspirations (see §5).

1. **NEVER throw into the host.** Every public entry point and every callback that runs at app runtime is wrapped so an internal failure degrades to a **no-op + a single rate-limited debug log** — never an exception that escapes into the host's call stack. No exception originating inside leak-radar may ever surface in a consumer's app.
2. **NEVER measurably slow the host.** Heap probing runs on a throttled timer with bounded work per tick. No synchronous heavy work on the UI/platform thread. Sampling budgets and intervals are config-driven with safe defaults. If the device is busy, prefer skipping a tick over blocking.
3. **Complete no-op in release.** All instrumentation is guarded behind `kDebugMode`/profile checks **and** an explicit opt-in flag, so the tree-shaker eliminates the machinery in release builds. The detector relies on the VM service / timers that have no business running in production — ensure none of it is reachable in a release build.
4. **Graceful "service unavailable."** When the VM service is absent, disabled, disconnected, or returns an error, `VmHeapProbe` degrades to a quiet no-op and the radar reports "not measured" — **never** a guessed/plausible-but-wrong number, and never a crash. Honest degradation only.
5. **No global side effects on import.** Importing the package does nothing. Behavior starts only on explicit `install()`.

If you cannot guarantee one of these for a change, the change does not ship.

---

## 4. Code style

Follows the repo's house style; key points:

- **Immutable hand-rolled value types — NOT `freezed`.** Model leak data as `@immutable final class` types with `final` fields, a `const` constructor where possible, explicit `==`/`hashCode`, and `copyWith`. Do **not** introduce `freezed` or `json_serializable` — the boilerplate does not win here.

```dart
import 'package:meta/meta.dart';

enum LeakSeverity { suspected, confirmed }

@immutable
final class LeakReport {
  const LeakReport({
    required this.objectType,
    required this.detectedAt,
    required this.severity,
    this.retainedFor,
  });

  final String objectType;
  final DateTime detectedAt;
  final LeakSeverity severity;
  final Duration? retainedFor;

  LeakReport copyWith({LeakSeverity? severity, Duration? retainedFor}) =>
      LeakReport(
        objectType: objectType,
        detectedAt: detectedAt,
        severity: severity ?? this.severity,
        retainedFor: retainedFor ?? this.retainedFor,
      );

  @override
  bool operator ==(Object other) =>
      other is LeakReport &&
      other.objectType == objectType &&
      other.detectedAt == detectedAt &&
      other.severity == severity &&
      other.retainedFor == retainedFor;

  @override
  int get hashCode => Object.hash(objectType, detectedAt, severity, retainedFor);
}
```

- **Immutability everywhere.** Return new objects; never mutate inputs. Prefer a single `LeakRadarConfig` value object over long parameter lists.
- **Small, focused files** (`<800` lines, ideally 200–400). High cohesion, low coupling.
- **Descriptive naming.** `camelCase` members, `PascalCase` types, `UPPER_SNAKE_CASE` constants, `is/has/should/can` for booleans. No abbreviations that aren't obvious.
- **No magic numbers.** Sampling intervals, budgets, thresholds, and buffer sizes are named constants or live in `LeakRadarConfig`.
- **Comprehensive error handling.** Handle errors explicitly at every boundary; never silently swallow (the safety-rule no-op path still logs once, rate-limited). Validate all external/VM-service data — never trust it.
- **No debug `print` noise in shipped code.** Use `dart:developer log()` gated behind debug + the rate limiter. No stray `print`, no leftover debug spew, no `// TODO` dumps in published surfaces.
- **Early returns over deep nesting** (max 4 levels). Functions stay under ~50 lines.

---

## 5. Testing requirements

New behavior ships with tests. Target the repo's **80% minimum** coverage. Three required tiers:

1. **Pure unit tests** — the core. `LeakAnalyzer` and all heuristics are tested with hand-built heap fixtures, **no VM, no mocks of `vm_service`**. Value types (`==`/`hashCode`/`copyWith`) are tested. This tier carries the bulk of coverage.
2. **Widget / golden tests** — exercise lifecycle-driven detection (e.g. a widget that leaks vs. one that disposes cleanly) and any DevTools-facing rendering. Goldens run on a **pinned** Flutter version only (renderer-sensitive); `--update-goldens` is disallowed in CI.
3. **Example-app coverage** — the shared `example/` app must build and exercise both packages; it is the manual/e2e bed and must stay runnable.

Safety invariants from §3 are **tested explicitly**: assert that a thrown-from-internals scenario degrades to a no-op, that a missing VM service yields "not measured" rather than a crash or fabricated number, and that nothing runs when the opt-in flag is off.

For the lint plugin: each rule has tests asserting it flags the bad pattern and does **not** flag the good pattern, plus fix-application tests where a fix exists.

Use AAA (Arrange-Act-Assert) structure and descriptive test names that state the behavior under test.

---

## 6. Documentation expectations

- **Dartdoc** every public symbol (the facade is small — there is no excuse). Document *behavior, safety guarantees, and the release no-op* on `LeakRadar` and `LeakRadarConfig`. Include at least one `/// ```dart` snippet on the main entrypoint.
- **Per-package `README.md`** (required for pub points): what it does, install, the minimal zero-config usage, the optional `track()` opt-in, the debug/profile-only behavior, and the recommended `analysis_options.yaml` snippet for the lint package (state clearly which rules are on-by-default vs opt-in).
- **Per-package `CHANGELOG.md`** (required): a parseable `## <version>` header matching `pubspec.yaml` for every release.
- **Runnable `example/`** co-located in each published package so pub.dev awards the example points; the top-level `example/` app is the richer demo.
- Keep `description` in each `pubspec.yaml` **60–180 chars** and set `topics:` for discoverability.

---

## 7. Melos workflow

Bootstrap once, then use the workspace scripts. Run the **same gate locally that CI runs** to avoid drift.

```bash
dart pub global activate melos     # one-time
melos bootstrap                    # resolve the workspace (shared lockfile)

melos run analyze                  # dart analyze --fatal-infos across the workspace
melos run format-check             # dart format --set-exit-if-changed .
melos run test                     # flutter/dart test per package
melos run custom_lint              # run the analyzer plugin over the repo (dogfood)
melos run pana                     # pub-points check on published packages

melos run ci                       # format-check + analyze + test (the full local gate)
```

- The repo **dogfoods its own lints**: `flutter_leak_radar` has `flutter_leak_radar_lint` as a `path:` dev dependency. `melos run custom_lint` must be clean before you push.
- CI runs a matrix over Flutter `stable` and `beta` so analyzer/SDK breakage surfaces early. Publishing is gated behind a `--dry-run`.

---

## 8. Commit & PR conventions

- **Conventional Commits with scopes** so `melos version` routes changes to the right package:
  - `feat(detector): add retained-element heuristic`
  - `fix(lint): stop flagging late-initialized controllers`
  - `docs(detector): document the track() opt-in`
- **Independent versioning per package** — the detector and the lint plugin evolve on different cadences; do not lockstep them. Pre-1.0, `feat` → minor, `fix` → patch; mark breaking changes with a `BREAKING CHANGE:` footer. After 1.0, **lint rule renames / severity changes are breaking** (they change users' CI outcomes).
- One logical change per PR. PR description references the relevant `docs/specs/` doc, lists the changes, and includes a test plan. CI (format, analyze, test, custom_lint, pana) must be green before review.
- Keep diffs surgical — no drive-by reformatting of untouched code.

---

## 9. Rules for AI agents

Read this before generating any change:

1. **Read the spec first.** Before implementing anything, read the relevant document in `docs/specs/`. The spec is authoritative; this file and the spec override your assumptions. If the spec is missing or ambiguous, ask / flag it — do not invent behavior.
2. **Respect public-API boundaries.** Never widen the facade. Add to `src/` and export via an explicit `show` only when the API genuinely needs to grow. Never make a consumer import from `src/`. Never let `vm_service` leak out of `VmHeapProbe` or into `LeakAnalyzer`.
3. **Honor the hard safety rules (§3) absolutely.** No throwing into the host, no release-mode runtime cost, graceful service-unavailable degradation, honest "not measured" over fabricated numbers. A change that risks any of these is wrong regardless of test status.
4. **Keep diffs surgical.** Change the minimum needed. No speculative abstractions (YAGNI), no unrelated refactors, no reformatting untouched files, no new dependencies without justification (and never `freezed`).
5. **Add tests for every change.** New heuristic → pure unit tests with fixtures. New rule → flags-bad / ignores-good tests. New safety path → an explicit invariant test. Run `melos run ci` and `melos run custom_lint` and confirm green before claiming done.
6. **No fabrication.** Don't invent metrics, API signatures, or VM-service behavior you haven't verified. If a value can't be truthfully computed, surface "not measured" — never a plausible-but-wrong number.
7. **Verify before claiming completion.** "Done" requires the gate actually passing — evidence, not assertion.
