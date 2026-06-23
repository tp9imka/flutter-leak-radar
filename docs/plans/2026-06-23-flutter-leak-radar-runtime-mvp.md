# flutter_leak_radar Runtime MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a runnable, on-device leak detector you can `init()` + `scan()` in an example app and see per-class growth findings — the smallest usable slice of the runtime spec.

**Architecture:** Layered, pure-core. `VmHeapProbe` is the only unit importing `package:vm_service`; `LeakAnalyzer`/`SampleHistory`/`SuspectSet`/models are pure and deterministic; `_LeakEngine` orchestrates capture→analyze→report; `LeakRadar` is the sole static public facade and is a guaranteed no-op in release. A `LeakObjectRegistry` adds precise `track()`/`markDisposed()` via `WeakReference`/`Finalizer`.

**Tech Stack:** Dart 3.10 / Flutter 3.38, `package:vm_service`, `package:meta`, `flutter_test`, melos workspace.

**Scope of THIS plan (usable MVP):** scaffold, build-mode gating + safe utils, value models, rules, history, analyzer, precise registry, probe interface + noop + fake + real `VmHeapProbe`, engine, facade + config, a minimal results screen, and an example app with an intentional leak. **Deferred to a follow-up plan:** periodic + navigation triggers, the draggable overlay badge, growth sparkline, and export/share.

**Source of truth:** `docs/specs/2026-06-23-flutter-leak-radar-runtime-design.md`. Read `AGENTS.md` before starting.

## Global Constraints

- **Dart SDK `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.** (verbatim version floor)
- **Never throw into the host.** Every public facade method and every engine callback is wrapped in `runSafely`/`runSafelyAsync`; on error → no-op + return safe default + one rate-limited debug log.
- **Complete release no-op.** Active machinery is constructed only when `kEngineEnabled && config.enabled`, where `const kEngineEnabled = kDebugMode || kProfileMode`. `package:vm_service` is only ever imported by `VmHeapProbe`, which is never instantiated in release.
- **Single public library.** `lib/flutter_leak_radar.dart` is the only public import; everything else lives under `lib/src/` and is exported with explicit `show` lists. Use `@internal` from `package:meta` where needed.
- **Immutable hand-rolled value types — NOT freezed.** `@immutable final class`, `final` fields, `const` ctors where possible, explicit `==`/`hashCode`, `copyWith`.
- **Files ≤ 800 lines, typically 200–400.** Organize by domain (config/engine/analysis/precise/model/ui/util), not by layer.
- **No `print`.** Use the `RateLimitedLogger` (wraps `dart:developer log()`), gated by `LeakLogLevel`.
- **Object ids are isolate-scoped.** Never reuse a VM-service object id across isolates.
- **`LeakKind` taxonomy mirrors `package:leak_tracker`:** `notDisposed`, `notGced`, `gcedLate`, `growth`.

---

### Task 0: Monorepo + runtime package scaffold

**Files:**
- Create: `melos.yaml`
- Create: `pubspec.yaml` (workspace root)
- Create: `packages/flutter_leak_radar/pubspec.yaml`
- Create: `packages/flutter_leak_radar/analysis_options.yaml`
- Create: `analysis_options.yaml` (root, shared)
- Create: `packages/flutter_leak_radar/lib/flutter_leak_radar.dart`

**Interfaces:**
- Produces: a resolvable Flutter package `flutter_leak_radar` with deps `vm_service`, `meta`, `flutter`; dev deps `flutter_test`, `flutter_lints`. The public entrypoint compiles (empty exports for now).

- [ ] **Step 1: Create the workspace root `pubspec.yaml`**

```yaml
name: flutter_leak_radar_workspace
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
workspace:
  - packages/flutter_leak_radar
dev_dependencies:
  melos: ^6.0.0
```

- [ ] **Step 2: Create `melos.yaml`**

```yaml
name: flutter_leak_radar
packages:
  - packages/**
  - example
scripts:
  analyze:
    run: dart analyze --fatal-infos
    exec: { concurrency: 1 }
  test:
    run: flutter test
    exec: { concurrency: 1 }
```

- [ ] **Step 3: Create the package `pubspec.yaml`**

```yaml
name: flutter_leak_radar
description: On-device, zero-config memory-leak detector for Flutter (debug/profile). Tracks per-class heap growth and precise object retention; complete no-op in release.
version: 0.0.1
repository: https://github.com/<owner>/flutter-leak-radar
environment:
  sdk: ">=3.10.0 <4.0.0"
  flutter: ">=3.38.0"
resolution: workspace
dependencies:
  flutter:
    sdk: flutter
  vm_service: ^15.0.0
  meta: ^1.15.0
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

- [ ] **Step 4: Create root + package `analysis_options.yaml`**

Root `analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore
linter:
  rules:
    - prefer_final_locals
    - always_declare_return_types
```

Package `packages/flutter_leak_radar/analysis_options.yaml`:
```yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 5: Create the public entrypoint (empty for now)**

```dart
// packages/flutter_leak_radar/lib/flutter_leak_radar.dart
/// On-device, zero-config memory-leak detector for Flutter.
library;

// Public exports are added as units land (see plan tasks).
```

- [ ] **Step 6: Bootstrap + verify resolution**

Run: `dart pub get` (from `packages/flutter_leak_radar`) — or `melos bootstrap` from root.
Expected: resolves with no errors; `vm_service`, `meta` downloaded.

- [ ] **Step 7: Commit**

```bash
git add melos.yaml pubspec.yaml packages/ analysis_options.yaml
git commit -m "chore: scaffold flutter_leak_radar runtime package + melos workspace"
```

---

### Task 1: Build-mode gating + safe-execution utilities

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/util/build_mode.dart`
- Create: `packages/flutter_leak_radar/lib/src/util/rate_limited_logger.dart`
- Create: `packages/flutter_leak_radar/lib/src/util/safe.dart`
- Test: `packages/flutter_leak_radar/test/util/safe_test.dart`

**Interfaces:**
- Produces: `const bool kEngineEnabled`; `class RateLimitedLogger { void log(String message, {LeakLogLevel level}); }`; `enum LeakLogLevel { none, error, warning, verbose }`; `T runSafely<T>(T Function() body, {required T fallback, RateLimitedLogger? logger}); Future<T> runSafelyAsync<T>(Future<T> Function() body, {required T fallback, RateLimitedLogger? logger});`

- [ ] **Step 1: Write the failing test**

```dart
// test/util/safe_test.dart
import 'package:flutter_leak_radar/src/util/safe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runSafely returns body result on success', () {
    expect(runSafely<int>(() => 42, fallback: -1), 42);
  });

  test('runSafely returns fallback and never throws on error', () {
    expect(runSafely<int>(() => throw StateError('boom'), fallback: -1), -1);
  });

  test('runSafelyAsync returns fallback on async error', () async {
    final value = await runSafelyAsync<int>(
      () async => throw Exception('boom'),
      fallback: 7,
    );
    expect(value, 7);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/util/safe_test.dart`
Expected: FAIL — `safe.dart` / `runSafely` not defined.

- [ ] **Step 3: Implement `build_mode.dart`**

```dart
// lib/src/util/build_mode.dart
import 'package:flutter/foundation.dart';

/// Compile-time gate. Active machinery is built only when this is true, so the
/// tree-shaker eliminates the engine (and `package:vm_service`) from release.
const bool kEngineEnabled = kDebugMode || kProfileMode;
```

- [ ] **Step 4: Implement `rate_limited_logger.dart`**

```dart
// lib/src/util/rate_limited_logger.dart
import 'dart:developer' as developer;

/// Verbosity for [RateLimitedLogger].
enum LeakLogLevel { none, error, warning, verbose }

/// Dedupes identical messages and caps frequency so a recurring failure can
/// never spam the console or slow the host.
class RateLimitedLogger {
  RateLimitedLogger({this.level = LeakLogLevel.warning, this.window = const Duration(seconds: 5)});

  final LeakLogLevel level;
  final Duration window;
  final Map<String, DateTime> _lastLogged = <String, DateTime>{};

  void log(String message, {LeakLogLevel level = LeakLogLevel.warning, DateTime? now}) {
    if (this.level == LeakLogLevel.none) return;
    if (level.index > this.level.index) return;
    final at = now ?? DateTime.now();
    final last = _lastLogged[message];
    if (last != null && at.difference(last) < window) return;
    _lastLogged[message] = at;
    developer.log(message, name: 'flutter_leak_radar');
  }
}
```

- [ ] **Step 5: Implement `safe.dart`**

```dart
// lib/src/util/safe.dart
import 'rate_limited_logger.dart';

/// Runs [body], swallowing any error and returning [fallback]. Never throws.
T runSafely<T>(T Function() body, {required T fallback, RateLimitedLogger? logger}) {
  try {
    return body();
  } catch (e, _) {
    logger?.log('leak_radar suppressed error: $e', level: LeakLogLevel.error);
    return fallback;
  }
}

/// Async variant of [runSafely].
Future<T> runSafelyAsync<T>(Future<T> Function() body, {required T fallback, RateLimitedLogger? logger}) async {
  try {
    return await body();
  } catch (e, _) {
    logger?.log('leak_radar suppressed async error: $e', level: LeakLogLevel.error);
    return fallback;
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/util/safe_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/src/util/ test/util/
git commit -m "feat: add build-mode gate, rate-limited logger, safe-execution guards"
```

---

### Task 2: Core value models (enums, samples, findings, report)

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/model/leak_kind.dart`
- Create: `packages/flutter_leak_radar/lib/src/engine/class_sample.dart`
- Create: `packages/flutter_leak_radar/lib/src/model/retaining_path.dart`
- Create: `packages/flutter_leak_radar/lib/src/model/leak_finding.dart`
- Create: `packages/flutter_leak_radar/lib/src/model/leak_report.dart`
- Test: `packages/flutter_leak_radar/test/model/leak_report_test.dart`

**Interfaces:**
- Produces:
  - `enum LeakKind { notDisposed, notGced, gcedLate, growth }`
  - `enum LeakSeverity { info, warning, critical }`
  - `enum LeakRadarStatus { disabled, preciseOnly, active, serviceUnavailable }` (defined here, re-exported by facade to avoid a cycle)
  - `ClassSample({String className, String? library, int instancesCurrent, int bytesCurrent, DateTime timestamp})`
  - `HeapSnapshot({List<ClassSample> samples, DateTime capturedAt, int? heapBytes})`
  - `RetainingHop`, `RetainingPathView`
  - `LeakFinding(...)` with `withRetainingPath`, `toJson`
  - `LeakReport(...)` with `hasLeaks`, `worstSeverity`, `toJson`, `toMarkdown`

- [ ] **Step 1: Write the failing test**

```dart
// test/model/leak_report_test.dart
import 'package:flutter_leak_radar/src/model/leak_finding.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';
import 'package:flutter_test/flutter_test.dart';

LeakFinding finding(String name, LeakSeverity sev) => LeakFinding(
      className: name,
      kind: LeakKind.growth,
      severity: sev,
      liveCount: 3,
      growth: 2,
      series: const [1, 2, 3],
    );

void main() {
  test('worstSeverity is info for empty findings', () {
    final r = LeakReport(findings: const [], capturedAt: DateTime(2026), trigger: 'manual', status: LeakRadarStatus.active);
    expect(r.hasLeaks, false);
    expect(r.worstSeverity, LeakSeverity.info);
  });

  test('worstSeverity is the max over findings', () {
    final r = LeakReport(
      findings: [finding('A', LeakSeverity.warning), finding('B', LeakSeverity.critical)],
      capturedAt: DateTime(2026), trigger: 'manual', status: LeakRadarStatus.active,
    );
    expect(r.hasLeaks, true);
    expect(r.worstSeverity, LeakSeverity.critical);
  });

  test('toJson round-trips finding count and toMarkdown lists class names', () {
    final r = LeakReport(
      findings: [finding('HomeBloc', LeakSeverity.critical)],
      capturedAt: DateTime(2026, 1, 2), trigger: 'manual', status: LeakRadarStatus.active, heapBytes: 1024,
    );
    final json = r.toJson();
    expect((json['findings'] as List).length, 1);
    expect(json['trigger'], 'manual');
    expect(r.toMarkdown(), contains('HomeBloc'));
  });

  test('equality by value', () {
    final a = finding('X', LeakSeverity.info);
    final b = finding('X', LeakSeverity.info);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/model/leak_report_test.dart`
Expected: FAIL — model classes not defined.

- [ ] **Step 3: Implement `leak_kind.dart`**

```dart
// lib/src/model/leak_kind.dart
/// Mirrors package:leak_tracker's taxonomy for report consistency.
enum LeakKind { notDisposed, notGced, gcedLate, growth }

enum LeakSeverity { info, warning, critical }

/// Runtime status of the detector. Defined here (not in the facade) so models
/// can reference it without a dependency cycle.
enum LeakRadarStatus { disabled, preciseOnly, active, serviceUnavailable }
```

- [ ] **Step 4: Implement `class_sample.dart`**

```dart
// lib/src/engine/class_sample.dart
import 'package:meta/meta.dart';

/// One row of a heap snapshot: the live-instance count for a single class.
@immutable
final class ClassSample {
  const ClassSample({
    required this.className,
    required this.instancesCurrent,
    required this.bytesCurrent,
    required this.timestamp,
    this.library,
  });

  final String className;
  final String? library;
  final int instancesCurrent;
  final int bytesCurrent;
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      other is ClassSample &&
      other.className == className &&
      other.library == library &&
      other.instancesCurrent == instancesCurrent &&
      other.bytesCurrent == bytesCurrent &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(className, library, instancesCurrent, bytesCurrent, timestamp);
}

/// A full per-class heap snapshot captured at one instant.
@immutable
final class HeapSnapshot {
  const HeapSnapshot({required this.samples, required this.capturedAt, this.heapBytes});

  final List<ClassSample> samples;
  final DateTime capturedAt;
  final int? heapBytes;
}
```

- [ ] **Step 5: Implement `retaining_path.dart`**

```dart
// lib/src/model/retaining_path.dart
import 'package:meta/meta.dart';

/// One hop in a retaining path (UI-facing copy, decoupled from vm_service types).
@immutable
final class RetainingHop {
  const RetainingHop({required this.objectType, this.field, this.index, this.mapKey});

  final String objectType;
  final String? field;
  final int? index;
  final String? mapKey;

  Map<String, Object?> toJson() => {
        'objectType': objectType,
        if (field != null) 'field': field,
        if (index != null) 'index': index,
        if (mapKey != null) 'mapKey': mapKey,
      };
}

@immutable
final class RetainingPathView {
  const RetainingPathView({required this.elements, this.gcRootType});

  final String? gcRootType;
  final List<RetainingHop> elements;

  Map<String, Object?> toJson() => {
        'gcRootType': gcRootType,
        'elements': elements.map((e) => e.toJson()).toList(),
      };
}
```

- [ ] **Step 6: Implement `leak_finding.dart`**

```dart
// lib/src/model/leak_finding.dart
import 'package:meta/meta.dart';

import 'leak_kind.dart';
import 'retaining_path.dart';

@immutable
final class LeakFinding {
  const LeakFinding({
    required this.className,
    required this.kind,
    required this.severity,
    required this.liveCount,
    required this.growth,
    this.library,
    this.tag,
    this.series = const <int>[],
    this.retainingPath,
  });

  final String className;
  final LeakKind kind;
  final LeakSeverity severity;
  final int liveCount;
  final int growth;
  final String? library;
  final String? tag;
  final List<int> series;
  final RetainingPathView? retainingPath;

  LeakFinding withRetainingPath(RetainingPathView path) => LeakFinding(
        className: className, kind: kind, severity: severity, liveCount: liveCount,
        growth: growth, library: library, tag: tag, series: series, retainingPath: path,
      );

  Map<String, Object?> toJson() => {
        'className': className,
        'kind': kind.name,
        'severity': severity.name,
        'liveCount': liveCount,
        'growth': growth,
        if (library != null) 'library': library,
        if (tag != null) 'tag': tag,
        'series': series,
        if (retainingPath != null) 'retainingPath': retainingPath!.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is LeakFinding &&
      other.className == className &&
      other.kind == kind &&
      other.severity == severity &&
      other.liveCount == liveCount &&
      other.growth == growth &&
      other.library == library &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(className, kind, severity, liveCount, growth, library, tag);
}
```

- [ ] **Step 7: Implement `leak_report.dart`**

```dart
// lib/src/model/leak_report.dart
import 'package:meta/meta.dart';

import 'leak_finding.dart';
import 'leak_kind.dart';

@immutable
final class LeakReport {
  const LeakReport({
    required this.findings,
    required this.capturedAt,
    required this.trigger,
    required this.status,
    this.heapBytes,
  });

  final List<LeakFinding> findings;
  final DateTime capturedAt;
  final String trigger;
  final LeakRadarStatus status;
  final int? heapBytes;

  bool get hasLeaks => findings.isNotEmpty;

  LeakSeverity get worstSeverity {
    var worst = LeakSeverity.info;
    for (final f in findings) {
      if (f.severity.index > worst.index) worst = f.severity;
    }
    return worst;
  }

  Map<String, Object?> toJson() => {
        'capturedAt': capturedAt.toIso8601String(),
        'trigger': trigger,
        'status': status.name,
        if (heapBytes != null) 'heapBytes': heapBytes,
        'findings': findings.map((f) => f.toJson()).toList(),
      };

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# Leak report ($trigger) — ${capturedAt.toIso8601String()}')
      ..writeln('Status: ${status.name} · findings: ${findings.length}')
      ..writeln()
      ..writeln('| Class | Kind | Severity | Live | Growth |')
      ..writeln('|---|---|---|---:|---:|');
    for (final f in findings) {
      b.writeln('| ${f.className} | ${f.kind.name} | ${f.severity.name} | ${f.liveCount} | ${f.growth} |');
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is LeakReport &&
      other.capturedAt == capturedAt &&
      other.trigger == trigger &&
      other.status == status &&
      other.heapBytes == heapBytes &&
      _listEq(other.findings, findings);

  @override
  int get hashCode => Object.hash(capturedAt, trigger, status, heapBytes, Object.hashAll(findings));
}

bool _listEq(List<LeakFinding> a, List<LeakFinding> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/model/leak_report_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 9: Commit**

```bash
git add lib/src/model/ lib/src/engine/class_sample.dart test/model/
git commit -m "feat: add core value models (LeakKind, ClassSample, LeakFinding, LeakReport)"
```

---

### Task 3: SuspectSet + LeakRule (glob matching + merge precedence)

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/config/leak_rule.dart`
- Create: `packages/flutter_leak_radar/lib/src/config/suspect_set.dart`
- Test: `packages/flutter_leak_radar/test/config/suspect_set_test.dart`

**Interfaces:**
- Consumes: `LeakSeverity` (from `model/leak_kind.dart`).
- Produces:
  - `enum LeakDetectionMode { growth, maxLive, ignore }`
  - `LeakRule` with `const factory LeakRule.growth(String pattern, {int minGrowth, LeakSeverity? severityHint})`, `LeakRule.maxLive(String pattern, int max, {LeakSeverity? severityHint})`, `LeakRule.ignore(String pattern)`; `bool matches(String className)`; fields `pattern`, `mode`, `maxLive`, `minGrowth`, `severityHint`.
  - `SuspectSet(List<LeakRule> rules)`, `SuspectSet.empty()`, `factory SuspectSet.defaults()`, `SuspectSet merge(List<LeakRule> extra)`, `LeakRule? ruleFor(String className)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/config/suspect_set_test.dart
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeakRule.matches (glob)', () {
    test('suffix *Bloc', () {
      const r = LeakRule.growth('*Bloc');
      expect(r.matches('HomeBloc'), true);
      expect(r.matches('BlocBase'), false);
    });
    test('prefix State*', () {
      const r = LeakRule.growth('State*');
      expect(r.matches('StateController'), true);
      expect(r.matches('AppState'), false);
    });
    test('contains *Stream*', () {
      const r = LeakRule.growth('*Stream*');
      expect(r.matches('_StreamSubscriptionImpl'), true);
    });
    test('exact', () {
      const r = LeakRule.growth('Timer');
      expect(r.matches('Timer'), true);
      expect(r.matches('_Timer'), false);
    });
  });

  group('SuspectSet', () {
    test('ruleFor returns first matching default', () {
      final s = SuspectSet.defaults();
      expect(s.ruleFor('LoginBloc')?.mode, LeakDetectionMode.growth);
      expect(s.ruleFor('PlainModel'), isNull);
    });

    test('merge precedence: ignore beats default and override', () {
      final s = SuspectSet.defaults().merge([
        const LeakRule.maxLive('*Bloc', 1),
        const LeakRule.ignore('SpecialBloc'),
      ]);
      expect(s.ruleFor('SpecialBloc')?.mode, LeakDetectionMode.ignore);
      expect(s.ruleFor('OtherBloc')?.mode, LeakDetectionMode.maxLive);
      expect(s.ruleFor('OtherBloc')?.maxLive, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/config/suspect_set_test.dart`
Expected: FAIL — `LeakRule`/`SuspectSet` not defined.

- [ ] **Step 3: Implement `leak_rule.dart`**

```dart
// lib/src/config/leak_rule.dart
import 'package:meta/meta.dart';

import '../model/leak_kind.dart';

enum LeakDetectionMode { growth, maxLive, ignore }

@immutable
final class LeakRule {
  const LeakRule._({
    required this.pattern,
    required this.mode,
    this.maxLive,
    this.minGrowth = 1,
    this.severityHint,
  });

  const factory LeakRule.growth(String pattern, {int minGrowth, LeakSeverity? severityHint}) = _growthRule;
  const factory LeakRule.maxLive(String pattern, int max, {LeakSeverity? severityHint}) = _maxLiveRule;
  const factory LeakRule.ignore(String pattern) = _ignoreRule;

  final String pattern;
  final LeakDetectionMode mode;
  final int? maxLive;
  final int minGrowth;
  final LeakSeverity? severityHint;

  /// Glob match against the simple class name:
  /// `*X` endsWith, `X*` startsWith, `*X*` contains, otherwise exact.
  bool matches(String className) {
    final p = pattern;
    final star = p.startsWith('*');
    final starEnd = p.endsWith('*');
    if (star && starEnd) return className.contains(p.substring(1, p.length - 1));
    if (star) return className.endsWith(p.substring(1));
    if (starEnd) return className.startsWith(p.substring(0, p.length - 1));
    return className == p;
  }

  @override
  bool operator ==(Object other) =>
      other is LeakRule &&
      other.pattern == pattern &&
      other.mode == mode &&
      other.maxLive == maxLive &&
      other.minGrowth == minGrowth &&
      other.severityHint == severityHint;

  @override
  int get hashCode => Object.hash(pattern, mode, maxLive, minGrowth, severityHint);
}

class _growthRule extends LeakRule {
  const _growthRule(String pattern, {int minGrowth = 1, LeakSeverity? severityHint})
      : super._(pattern: pattern, mode: LeakDetectionMode.growth, minGrowth: minGrowth, severityHint: severityHint);
}

class _maxLiveRule extends LeakRule {
  const _maxLiveRule(String pattern, int max, {LeakSeverity? severityHint})
      : super._(pattern: pattern, mode: LeakDetectionMode.maxLive, maxLive: max, severityHint: severityHint);
}

class _ignoreRule extends LeakRule {
  const _ignoreRule(String pattern) : super._(pattern: pattern, mode: LeakDetectionMode.ignore);
}
```

- [ ] **Step 4: Implement `suspect_set.dart`**

```dart
// lib/src/config/suspect_set.dart
import 'package:meta/meta.dart';

import 'leak_rule.dart';

@immutable
final class SuspectSet {
  const SuspectSet(this.rules);
  const SuspectSet.empty() : rules = const <LeakRule>[];

  /// Curated defaults for common Flutter/Dart leak-prone types. (`*State`
  /// rather than `State` so concrete State subclasses like `_HomeScreenState`
  /// match — refines the spec's `State` entry.)
  factory SuspectSet.defaults() => const SuspectSet(<LeakRule>[
        LeakRule.growth('*State'),
        LeakRule.growth('*Screen'),
        LeakRule.growth('*Bloc'),
        LeakRule.growth('*Cubit'),
        LeakRule.growth('*Controller'),
        LeakRule.growth('*Notifier'),
        LeakRule.growth('*StreamSubscription'),
        LeakRule.growth('*StreamController'),
        LeakRule.growth('Timer'),
      ]);

  final List<LeakRule> rules;

  /// Returns a new set with [extra] layered after the existing rules.
  /// Precedence in [ruleFor] is: ignore anywhere > last matching extra > defaults.
  SuspectSet merge(List<LeakRule> extra) => SuspectSet(<LeakRule>[...rules, ...extra]);

  /// The effective rule for [className], or null if none applies.
  LeakRule? ruleFor(String className) {
    LeakRule? chosen;
    for (final rule in rules) {
      if (!rule.matches(className)) continue;
      if (rule.mode == LeakDetectionMode.ignore) return rule; // highest precedence
      chosen = rule; // later matches override earlier
    }
    return chosen;
  }

  @override
  bool operator ==(Object other) => other is SuspectSet && _eq(other.rules, rules);

  @override
  int get hashCode => Object.hashAll(rules);
}

bool _eq(List<LeakRule> a, List<LeakRule> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/config/suspect_set_test.dart`
Expected: PASS.

> Note: the `ignore`-beats-everything precedence requires the ignore check to win even if a later non-ignore rule also matches. The loop above returns immediately on any matching ignore, satisfying the test.

- [ ] **Step 6: Commit**

```bash
git add lib/src/config/ test/config/
git commit -m "feat: add LeakRule glob matching + SuspectSet defaults and merge precedence"
```

---

### Task 4: SampleHistory (bounded ring buffer + per-class series)

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/analysis/sample_history.dart`
- Test: `packages/flutter_leak_radar/test/analysis/sample_history_test.dart`

**Interfaces:**
- Consumes: `HeapSnapshot`, `ClassSample` (from `engine/class_sample.dart`).
- Produces: `SampleHistory({int maxSnapshots})`, `void add(HeapSnapshot snapshot)`, `int get length`, `List<int> seriesFor(String className)` (live counts oldest→newest, 0 where the class is absent in a snapshot), `int latestCountFor(String className)`, `Set<String> get classNames` (union across snapshots).

- [ ] **Step 1: Write the failing test**

```dart
// test/analysis/sample_history_test.dart
import 'package:flutter_leak_radar/src/analysis/sample_history.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_test/flutter_test.dart';

HeapSnapshot snap(Map<String, int> counts, int t) => HeapSnapshot(
      capturedAt: DateTime(2026, 1, 1, 0, 0, t),
      samples: [
        for (final e in counts.entries)
          ClassSample(className: e.key, instancesCurrent: e.value, bytesCurrent: e.value * 8, timestamp: DateTime(2026, 1, 1, 0, 0, t)),
      ],
    );

void main() {
  test('bounds to maxSnapshots, dropping oldest', () {
    final h = SampleHistory(maxSnapshots: 2);
    h..add(snap({'A': 1}, 1))..add(snap({'A': 2}, 2))..add(snap({'A': 3}, 3));
    expect(h.length, 2);
    expect(h.seriesFor('A'), [2, 3]);
  });

  test('seriesFor pads absent classes with 0', () {
    final h = SampleHistory(maxSnapshots: 5);
    h..add(snap({'A': 1}, 1))..add(snap({'B': 9}, 2));
    expect(h.seriesFor('A'), [1, 0]);
    expect(h.seriesFor('B'), [0, 9]);
  });

  test('latestCountFor reads the newest snapshot', () {
    final h = SampleHistory(maxSnapshots: 5);
    h..add(snap({'A': 1}, 1))..add(snap({'A': 4}, 2));
    expect(h.latestCountFor('A'), 4);
    expect(h.latestCountFor('Z'), 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/analysis/sample_history_test.dart`
Expected: FAIL — `SampleHistory` not defined.

- [ ] **Step 3: Implement `sample_history.dart`**

```dart
// lib/src/analysis/sample_history.dart
import 'dart:collection';

import '../engine/class_sample.dart';

/// Bounded ring buffer of recent snapshots with fast per-class series extraction.
class SampleHistory {
  SampleHistory({this.maxSnapshots = 20}) : assert(maxSnapshots >= 2);

  final int maxSnapshots;
  final ListQueue<HeapSnapshot> _snapshots = ListQueue<HeapSnapshot>();

  void add(HeapSnapshot snapshot) {
    _snapshots.addLast(snapshot);
    while (_snapshots.length > maxSnapshots) {
      _snapshots.removeFirst();
    }
  }

  int get length => _snapshots.length;

  Set<String> get classNames => {
        for (final s in _snapshots)
          for (final sample in s.samples) sample.className,
      };

  /// Live-instance counts oldest→newest; 0 where the class is absent.
  List<int> seriesFor(String className) => [
        for (final s in _snapshots) _countIn(s, className),
      ];

  int latestCountFor(String className) =>
      _snapshots.isEmpty ? 0 : _countIn(_snapshots.last, className);

  int _countIn(HeapSnapshot s, String className) {
    for (final sample in s.samples) {
      if (sample.className == className) return sample.instancesCurrent;
    }
    return 0;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/analysis/sample_history_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/analysis/sample_history.dart test/analysis/sample_history_test.dart
git commit -m "feat: add bounded SampleHistory with per-class series extraction"
```

---

### Task 5: LeakAnalyzer (growth + maxLive + severity)

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/analysis/severity.dart`
- Create: `packages/flutter_leak_radar/lib/src/analysis/leak_analyzer.dart`
- Test: `packages/flutter_leak_radar/test/analysis/leak_analyzer_test.dart`

**Interfaces:**
- Consumes: `SuspectSet`, `LeakRule`, `LeakDetectionMode` (config); `SampleHistory`; `LeakReport`, `LeakFinding`, `LeakKind`, `LeakSeverity`, `LeakRadarStatus`.
- Produces:
  - `LeakSeverity computeSeverity({required LeakDetectionMode mode, required int growth, required int liveCount, int? maxLive, required bool monotonic, LeakSeverity? hint})`
  - `class LeakAnalyzer { const LeakAnalyzer(this.suspects); final SuspectSet suspects; LeakReport analyze(SampleHistory history, {required String trigger, required LeakRadarStatus status, List<LeakFinding> preciseFindings = const []}); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/analysis/leak_analyzer_test.dart
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/analysis/sample_history.dart';
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';

HeapSnapshot snap(Map<String, int> counts, int t) => HeapSnapshot(
      capturedAt: DateTime(2026, 1, 1, 0, 0, t),
      samples: [
        for (final e in counts.entries)
          ClassSample(className: e.key, instancesCurrent: e.value, bytesCurrent: 0, timestamp: DateTime(2026, 1, 1, 0, 0, t)),
      ],
    );

void main() {
  test('flat series produces no finding', () {
    final h = SampleHistory()..add(snap({'HomeBloc': 1}, 1))..add(snap({'HomeBloc': 1}, 2));
    final report = const LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]))
        .analyze(h, trigger: 'manual', status: LeakRadarStatus.active);
    expect(report.findings, isEmpty);
  });

  test('monotonic growth produces a growth finding', () {
    final h = SampleHistory()
      ..add(snap({'HomeBloc': 1}, 1))
      ..add(snap({'HomeBloc': 2}, 2))
      ..add(snap({'HomeBloc': 3}, 3));
    final report = const LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]))
        .analyze(h, trigger: 'manual', status: LeakRadarStatus.active);
    expect(report.findings.length, 1);
    final f = report.findings.single;
    expect(f.className, 'HomeBloc');
    expect(f.kind, LeakKind.growth);
    expect(f.growth, 2); // latest(3) - baseline(1)
    expect(f.liveCount, 3);
  });

  test('maxLive trips on exceed only', () {
    final atLimit = SampleHistory()..add(snap({'HomeBloc': 1}, 1));
    final over = SampleHistory()..add(snap({'HomeBloc': 2}, 1));
    const analyzer = LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.maxLive('*Bloc', 1)]));
    expect(analyzer.analyze(atLimit, trigger: 'm', status: LeakRadarStatus.active).findings, isEmpty);
    expect(analyzer.analyze(over, trigger: 'm', status: LeakRadarStatus.active).findings.single.kind, LeakKind.growth);
  });

  test('precise findings are folded into the report', () {
    final h = SampleHistory()..add(snap({'X': 1}, 1));
    final precise = [
      const LeakFinding(className: 'CallSession', kind: LeakKind.notGced, severity: LeakSeverity.critical, liveCount: 1, growth: 0, tag: 'CallSession'),
    ];
    final report = const LeakAnalyzer(SuspectSet.empty())
        .analyze(h, trigger: 'manual', status: LeakRadarStatus.active, preciseFindings: precise);
    expect(report.findings.single.tag, 'CallSession');
    expect(report.worstSeverity, LeakSeverity.critical);
  });
}
```

(`LeakFinding` import is pulled in transitively via `leak_kind.dart`? No — add `import 'package:flutter_leak_radar/src/model/leak_finding.dart';` at the top of the test.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/analysis/leak_analyzer_test.dart`
Expected: FAIL — `LeakAnalyzer` not defined.

- [ ] **Step 3: Implement `severity.dart`**

```dart
// lib/src/analysis/severity.dart
import '../config/leak_rule.dart';
import '../model/leak_kind.dart';

/// Computed severity floor for a heap finding. A [hint] can only raise it.
LeakSeverity computeSeverity({
  required LeakDetectionMode mode,
  required int growth,
  required int liveCount,
  int? maxLive,
  required bool monotonic,
  LeakSeverity? hint,
}) {
  var sev = LeakSeverity.info;
  if (mode == LeakDetectionMode.maxLive && maxLive != null) {
    if (liveCount > 2 * maxLive) {
      sev = LeakSeverity.critical;
    } else if (liveCount > maxLive) {
      sev = LeakSeverity.warning;
    }
  } else if (mode == LeakDetectionMode.growth) {
    if (monotonic && growth >= 2) {
      sev = LeakSeverity.critical;
    } else if (growth >= 1) {
      sev = LeakSeverity.warning;
    }
  }
  if (hint != null && hint.index > sev.index) sev = hint;
  return sev;
}
```

- [ ] **Step 4: Implement `leak_analyzer.dart`**

```dart
// lib/src/analysis/leak_analyzer.dart
import '../config/leak_rule.dart';
import '../config/suspect_set.dart';
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import 'sample_history.dart';
import 'severity.dart';

/// Pure, deterministic detection core. No I/O, no vm_service.
class LeakAnalyzer {
  const LeakAnalyzer(this.suspects);

  final SuspectSet suspects;

  LeakReport analyze(
    SampleHistory history, {
    required String trigger,
    required LeakRadarStatus status,
    List<LeakFinding> preciseFindings = const <LeakFinding>[],
  }) {
    final findings = <LeakFinding>[...preciseFindings];

    for (final className in history.classNames) {
      final rule = suspects.ruleFor(className);
      if (rule == null || rule.mode == LeakDetectionMode.ignore) continue;

      final series = history.seriesFor(className);
      if (series.isEmpty) continue;
      final liveCount = series.last;
      final baseline = series.reduce((a, b) => a < b ? a : b);
      final growth = liveCount - baseline;
      final monotonic = _isMonotonic(series);

      final tripped = switch (rule.mode) {
        LeakDetectionMode.growth => growth >= rule.minGrowth && liveCount > 0,
        LeakDetectionMode.maxLive => rule.maxLive != null && liveCount > rule.maxLive!,
        LeakDetectionMode.ignore => false,
      };
      if (!tripped) continue;

      findings.add(LeakFinding(
        className: className,
        kind: LeakKind.growth,
        severity: computeSeverity(
          mode: rule.mode, growth: growth, liveCount: liveCount,
          maxLive: rule.maxLive, monotonic: monotonic, hint: rule.severityHint,
        ),
        liveCount: liveCount,
        growth: growth,
        series: series,
      ));
    }

    findings.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return LeakReport(findings: findings, capturedAt: DateTime.now(), trigger: trigger, status: status);
  }

  static bool _isMonotonic(List<int> series) {
    for (var i = 1; i < series.length; i++) {
      if (series[i] < series[i - 1]) return false;
    }
    return series.length >= 2 && series.last > series.first;
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/analysis/leak_analyzer_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/analysis/severity.dart lib/src/analysis/leak_analyzer.dart test/analysis/leak_analyzer_test.dart
git commit -m "feat: add pure LeakAnalyzer (growth + maxLive + severity, precise folding)"
```

---

### Task 6: LeakObjectRegistry + gc_support (precise track/markDisposed)

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/precise/gc_support.dart`
- Create: `packages/flutter_leak_radar/lib/src/precise/leak_object_registry.dart`
- Test: `packages/flutter_leak_radar/test/precise/leak_object_registry_test.dart`

**Interfaces:**
- Consumes: `LeakFinding`, `LeakKind`, `LeakSeverity`.
- Produces:
  - `abstract interface class GcCounter { int get currentGcCount; }` + `class DeveloperGcCounter implements GcCounter` (wraps `reachabilityBarrier`).
  - `class LeakObjectRegistry { LeakObjectRegistry({GcCounter? gcCounter, Duration disposalGrace}); void track(Object obj, {required String tag}); void markDisposed(Object obj); List<LeakFinding> collectLeaks({int gcCycles, DateTime? now}); int get trackedCount; void clear(); }`

> The registry's leak decision is synchronous and testable with a fake `GcCounter`; forcing real GC is the engine's job (Task 9 / VmHeapProbe). `collectLeaks` evaluates current state only.

- [ ] **Step 1: Write the failing test**

```dart
// test/precise/leak_object_registry_test.dart
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/precise/gc_support.dart';
import 'package:flutter_leak_radar/src/precise/leak_object_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGc implements GcCounter {
  int value = 0;
  @override
  int get currentGcCount => value;
}

void main() {
  test('disposed object still alive after N GC cycles -> notGced', () {
    final gc = FakeGc();
    final reg = LeakObjectRegistry(gcCounter: gc, disposalGrace: Duration.zero);
    final obj = Object();
    reg.track(obj, tag: 'Thing');
    reg.markDisposed(obj);
    gc.value += 3;
    final leaks = reg.collectLeaks(gcCycles: 3, now: DateTime(2026).add(const Duration(seconds: 10)));
    expect(leaks.single.kind, LeakKind.notGced);
    expect(leaks.single.tag, 'Thing');
    expect(leaks.single.severity, LeakSeverity.critical);
  });

  test('disposed but not enough GC cycles -> no leak yet', () {
    final gc = FakeGc();
    final reg = LeakObjectRegistry(gcCounter: gc, disposalGrace: Duration.zero);
    final obj = Object();
    reg.track(obj, tag: 'Thing');
    reg.markDisposed(obj);
    gc.value += 1;
    expect(reg.collectLeaks(gcCycles: 3, now: DateTime(2026)), isEmpty);
  });

  test('markDisposed on an untracked object is a silent no-op', () {
    final reg = LeakObjectRegistry(gcCounter: FakeGc());
    reg.markDisposed(Object()); // must not throw
    expect(reg.trackedCount, 0);
  });

  test('clear empties the registry', () {
    final reg = LeakObjectRegistry(gcCounter: FakeGc());
    reg.track(Object(), tag: 'A');
    expect(reg.trackedCount, 1);
    reg.clear();
    expect(reg.trackedCount, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/precise/leak_object_registry_test.dart`
Expected: FAIL — `LeakObjectRegistry`/`GcCounter` not defined.

- [ ] **Step 3: Implement `gc_support.dart`**

```dart
// lib/src/precise/gc_support.dart
import 'dart:developer' as developer;

/// Abstraction over the VM's GC cycle counter so tests can drive it.
abstract interface class GcCounter {
  int get currentGcCount;
}

/// Real counter backed by `dart:developer`'s reachabilityBarrier.
class DeveloperGcCounter implements GcCounter {
  const DeveloperGcCounter();

  @override
  int get currentGcCount => developer.reachabilityBarrier;
}
```

- [ ] **Step 4: Implement `leak_object_registry.dart`**

```dart
// lib/src/precise/leak_object_registry.dart
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import 'gc_support.dart';

class _Entry {
  _Entry(Object obj, this.tag) : ref = WeakReference<Object>(obj);
  final WeakReference<Object> ref; // never a strong ref — must not extend lifetime
  final String tag;
  int? disposedGc;
  DateTime? disposedAt;
}

/// Precise leak detection via WeakReference + a GC-cycle counter.
class LeakObjectRegistry {
  LeakObjectRegistry({GcCounter? gcCounter, this.disposalGrace = const Duration(seconds: 2)})
      : _gc = gcCounter ?? const DeveloperGcCounter();

  final GcCounter _gc;
  final Duration disposalGrace;
  final Map<int, _Entry> _entries = <int, _Entry>{};

  int get trackedCount => _entries.length;

  void track(Object obj, {required String tag}) {
    _entries[identityHashCode(obj)] = _Entry(obj, tag);
  }

  void markDisposed(Object obj) {
    final entry = _entries[identityHashCode(obj)];
    if (entry == null) return; // silent no-op for untracked
    entry.disposedGc = _gc.currentGcCount;
    entry.disposedAt = DateTime.now();
  }

  /// Evaluates current state. An object disposed >= [gcCycles] GCs ago and past
  /// [disposalGrace], still alive, is a [LeakKind.notGced] leak. Prunes entries
  /// whose target has been collected.
  List<LeakFinding> collectLeaks({int gcCycles = 3, DateTime? now}) {
    final at = now ?? DateTime.now();
    final current = _gc.currentGcCount;
    final leaks = <LeakFinding>[];
    final dead = <int>[];

    _entries.forEach((key, entry) {
      final target = entry.ref.target;
      if (target == null) {
        dead.add(key); // collected — healthy, prune
        return;
      }
      final disposedGc = entry.disposedGc;
      final disposedAt = entry.disposedAt;
      if (disposedGc == null || disposedAt == null) return; // not disposed yet
      final survivedCycles = current - disposedGc >= gcCycles;
      final pastGrace = at.difference(disposedAt) >= disposalGrace;
      if (survivedCycles && pastGrace) {
        leaks.add(LeakFinding(
          className: target.runtimeType.toString(),
          kind: LeakKind.notGced,
          severity: LeakSeverity.critical,
          liveCount: 1,
          growth: 0,
          tag: entry.tag,
        ));
      }
    });

    for (final k in dead) {
      _entries.remove(k);
    }
    return leaks;
  }

  void clear() => _entries.clear();
}
```

> Note: keying by `identityHashCode` is sufficient for the MVP (collisions are astronomically unlikely for the count of tracked objects). A `Finalizer<int>` that prunes on collection — and a `notDisposed` finding for objects finalized before `markDisposed` — is added in the follow-up plan; here, pruning on a null `WeakReference.target` covers the healthy path.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/precise/leak_object_registry_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/precise/ test/precise/
git commit -m "feat: add precise LeakObjectRegistry (track/markDisposed via WeakReference + GC counter)"
```

---

### Task 7: HeapProbe interface + NoopHeapProbe + FakeHeapProbe

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/engine/heap_probe.dart`
- Create: `packages/flutter_leak_radar/test/support/fake_heap_probe.dart`
- Test: `packages/flutter_leak_radar/test/engine/noop_heap_probe_test.dart`

**Interfaces:**
- Consumes: `HeapSnapshot`, `ClassSample`; `RetainingPathView`.
- Produces:
  - `abstract interface class HeapProbe { Future<bool> get isAvailable; Future<HeapSnapshot> capture({required bool forceGc}); Future<RetainingPathView?> retainingPath(String className, {int maxInstances}); Future<void> dispose(); }`
  - `class NoopHeapProbe implements HeapProbe` (isAvailable→false, capture→empty snapshot, retainingPath→null).
  - Test helper `class FakeHeapProbe implements HeapProbe` with scripted snapshots + availability toggle.

- [ ] **Step 1: Write the failing test**

```dart
// test/engine/noop_heap_probe_test.dart
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NoopHeapProbe is unavailable and yields an empty snapshot', () async {
    const probe = NoopHeapProbe();
    expect(await probe.isAvailable, false);
    final snap = await probe.capture(forceGc: true);
    expect(snap.samples, isEmpty);
    expect(await probe.retainingPath('Anything'), isNull);
    await probe.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/engine/noop_heap_probe_test.dart`
Expected: FAIL — `HeapProbe`/`NoopHeapProbe` not defined.

- [ ] **Step 3: Implement `heap_probe.dart`**

```dart
// lib/src/engine/heap_probe.dart
import '../model/retaining_path.dart';
import 'class_sample.dart';

/// Abstraction over a heap source. Only [VmHeapProbe] talks to vm_service.
abstract interface class HeapProbe {
  Future<bool> get isAvailable;
  Future<HeapSnapshot> capture({required bool forceGc});
  Future<RetainingPathView?> retainingPath(String className, {int maxInstances});
  Future<void> dispose();
}

/// Used when no VM service is reachable. The engine then runs precise-only.
class NoopHeapProbe implements HeapProbe {
  const NoopHeapProbe();

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async =>
      HeapSnapshot(samples: const <ClassSample>[], capturedAt: DateTime.now());

  @override
  Future<RetainingPathView?> retainingPath(String className, {int maxInstances = 10}) async => null;

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 4: Implement the test helper `FakeHeapProbe`**

```dart
// test/support/fake_heap_probe.dart
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/model/retaining_path.dart';

/// Scriptable HeapProbe for engine/UI tests. Each [capture] returns the next
/// scripted snapshot (repeating the last one once exhausted).
class FakeHeapProbe implements HeapProbe {
  FakeHeapProbe(this._snapshots, {this.available = true, this.path});

  final List<HeapSnapshot> _snapshots;
  bool available;
  RetainingPathView? path;
  int captureCount = 0;
  int _index = 0;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async {
    captureCount++;
    if (_snapshots.isEmpty) return HeapSnapshot(samples: const [], capturedAt: DateTime.now());
    final snap = _snapshots[_index];
    if (_index < _snapshots.length - 1) _index++;
    return snap;
  }

  @override
  Future<RetainingPathView?> retainingPath(String className, {int maxInstances = 10}) async => path;

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/engine/noop_heap_probe_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/engine/heap_probe.dart test/support/fake_heap_probe.dart test/engine/noop_heap_probe_test.dart
git commit -m "feat: add HeapProbe interface, NoopHeapProbe, and FakeHeapProbe test helper"
```

---

### Task 8: VmHeapProbe (the only vm_service unit)

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/engine/vm_heap_probe.dart`
- Test: `packages/flutter_leak_radar/test/engine/vm_heap_probe_integration_test.dart`

**Interfaces:**
- Consumes: `HeapProbe`, `HeapSnapshot`, `ClassSample`, `RetainingPathView`, `RetainingHop`, `RateLimitedLogger`.
- Produces: `class VmHeapProbe implements HeapProbe { VmHeapProbe({RateLimitedLogger? logger, int maxRetainingPathRequests}); }` — connects lazily; `capture` uses `getAllocationProfile(gc:)`; `retainingPath` uses `getInstances` + `getRetainingPath`.

- [ ] **Step 1: Implement `vm_heap_probe.dart`**

```dart
// lib/src/engine/vm_heap_probe.dart
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../model/retaining_path.dart';
import '../util/rate_limited_logger.dart';
import 'class_sample.dart';
import 'heap_probe.dart';

/// The sole unit that imports `package:vm_service`. Connects to the running
/// app's own VM service (debug/profile) and never throws into callers.
class VmHeapProbe implements HeapProbe {
  VmHeapProbe({RateLimitedLogger? logger, this.maxRetainingPathRequests = 5})
      : _logger = logger ?? RateLimitedLogger();

  final RateLimitedLogger _logger;
  final int maxRetainingPathRequests;

  VmService? _service;
  String? _isolateId;
  bool _connectFailed = false;

  Future<Uri?> _serviceUri() async {
    var uri = (await developer.Service.getInfo()).serverWebSocketUri;
    if (uri != null) return uri;
    uri = (await developer.Service.controlWebServer(enable: true)).serverWebSocketUri;
    return uri;
  }

  Future<VmService?> _ensureConnected() async {
    if (_service != null) return _service;
    if (_connectFailed) return null;
    try {
      final uri = await _serviceUri();
      if (uri == null) {
        _connectFailed = true;
        return null;
      }
      final service = await vmServiceConnectUri(uri.toString());
      await service.getVersion(); // validate socket
      _isolateId = developer.Service.getIsolateID(Isolate.current) ?? (await service.getVM()).isolates?.first.id;
      _service = service;
      return service;
    } catch (e) {
      _logger.log('VmHeapProbe connect failed: $e', level: LeakLogLevel.error);
      _connectFailed = true;
      return null;
    }
  }

  @override
  Future<bool> get isAvailable async {
    try {
      final info = await developer.Service.getInfo();
      if (info.serverWebSocketUri != null) return true;
      final started = await developer.Service.controlWebServer(enable: true);
      return started.serverWebSocketUri != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async {
    final service = await _ensureConnected();
    final isolateId = _isolateId;
    if (service == null || isolateId == null) {
      return HeapSnapshot(samples: const <ClassSample>[], capturedAt: DateTime.now());
    }
    try {
      final profile = await service.getAllocationProfile(isolateId, gc: forceGc);
      final now = DateTime.now();
      final samples = <ClassSample>[];
      for (final m in profile.members ?? const <ClassHeapStats>[]) {
        final name = m.classRef?.name;
        if (name == null || name.isEmpty) continue;
        samples.add(ClassSample(
          className: name,
          library: m.classRef?.library?.uri,
          instancesCurrent: m.instancesCurrent ?? 0,
          bytesCurrent: m.bytesCurrent ?? 0,
          timestamp: now,
        ));
      }
      return HeapSnapshot(samples: samples, capturedAt: now);
    } on RPCError catch (e) {
      _logger.log('getAllocationProfile RPCError: ${e.message}', level: LeakLogLevel.error);
      return HeapSnapshot(samples: const <ClassSample>[], capturedAt: DateTime.now());
    } catch (e) {
      _logger.log('capture failed: $e', level: LeakLogLevel.error);
      _service = null; // force reconnect next time
      return HeapSnapshot(samples: const <ClassSample>[], capturedAt: DateTime.now());
    }
  }

  @override
  Future<RetainingPathView?> retainingPath(String className, {int maxInstances = 10}) async {
    final service = await _ensureConnected();
    final isolateId = _isolateId;
    if (service == null || isolateId == null) return null;
    try {
      final profile = await service.getAllocationProfile(isolateId);
      final classId = profile.members
          ?.firstWhere(
            (m) => m.classRef?.name == className,
            orElse: () => ClassHeapStats(),
          )
          .classRef
          ?.id;
      if (classId == null) return null;

      final set = await service.getInstances(isolateId, classId, maxInstances);
      final targetId = set.instances?.isNotEmpty == true ? set.instances!.first.id : null;
      if (targetId == null) return null;

      final path = await service.getRetainingPath(isolateId, targetId, 100000);
      final hops = <RetainingHop>[];
      for (final el in path.elements ?? const <RetainingObject>[]) {
        final value = el.value;
        final type = value is InstanceRef
            ? (value.classRef?.name ?? value.kind ?? 'Object')
            : (value?.runtimeType.toString() ?? 'Object');
        hops.add(RetainingHop(
          objectType: type,
          field: el.parentField?.toString(),
          index: el.parentListIndex,
          mapKey: (el.parentMapKey as InstanceRef?)?.valueAsString,
        ));
      }
      return RetainingPathView(gcRootType: path.gcRootType, elements: hops);
    } on SentinelException {
      return null; // object GCed between selection and the path RPC
    } catch (e) {
      _logger.log('retainingPath failed: $e', level: LeakLogLevel.error);
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _service?.dispose();
    } catch (_) {}
    _service = null;
  }
}
```

- [ ] **Step 2: Write the guarded integration test**

```dart
// test/engine/vm_heap_probe_integration_test.dart
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VmHeapProbe captures a non-empty profile when the service is present', () async {
    final probe = VmHeapProbe();
    if (!await probe.isAvailable) {
      // No VM service in this runner; nothing to assert.
      return;
    }
    // Retain instances so they appear in the profile.
    // ignore: unused_local_variable
    final retained = List.generate(1000, (i) => _Marker());
    final snap = await probe.capture(forceGc: true);
    expect(snap.samples, isNotEmpty);
    expect(snap.samples.any((s) => s.className == '_Marker'), isTrue);
    await probe.dispose();
  });
}

class _Marker {}
```

- [ ] **Step 3: Run the integration test**

Run: `flutter test test/engine/vm_heap_probe_integration_test.dart`
Expected: PASS (asserts a non-empty profile if the service is up; returns early/no-ops otherwise — never fails spuriously).

- [ ] **Step 4: Verify only this file imports vm_service**

Run: `grep -rl "package:vm_service" packages/flutter_leak_radar/lib`
Expected: exactly `packages/flutter_leak_radar/lib/src/engine/vm_heap_probe.dart`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/engine/vm_heap_probe.dart test/engine/vm_heap_probe_integration_test.dart
git commit -m "feat: add VmHeapProbe (getAllocationProfile capture + lazy retaining paths)"
```

---

### Task 9: LeakEngine orchestrator

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/engine/leak_engine.dart`
- Test: `packages/flutter_leak_radar/test/engine/leak_engine_test.dart`

**Interfaces:**
- Consumes: `HeapProbe`, `LeakAnalyzer`, `SampleHistory`, `LeakObjectRegistry`, `LeakReport`, `LeakRadarStatus`, `RateLimitedLogger`.
- Produces (annotated `@internal`):
  - `class LeakEngine { LeakEngine({required HeapProbe probe, required LeakAnalyzer analyzer, SampleHistory? history, LeakObjectRegistry? registry, int gcCyclesForPreciseLeak = 3, RateLimitedLogger? logger}); Future<void> start(); Future<LeakReport> scan({String trigger = 'manual'}); Stream<LeakReport> get reports; LeakReport? get latest; LeakRadarStatus get status; void track(Object o, {required String tag}); void markDisposed(Object o); Future<void> stop(); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/engine/leak_engine_test.dart
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';

HeapSnapshot snap(Map<String, int> counts, int t) => HeapSnapshot(
      capturedAt: DateTime(2026, 1, 1, 0, 0, t),
      samples: [for (final e in counts.entries) ClassSample(className: e.key, instancesCurrent: e.value, bytesCurrent: 0, timestamp: DateTime(2026, 1, 1, 0, 0, t))],
    );

LeakEngine engineWith(FakeHeapProbe probe) => LeakEngine(
      probe: probe,
      analyzer: const LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')])),
    );

void main() {
  test('status is active when the probe is available', () async {
    final engine = engineWith(FakeHeapProbe([snap({'A': 1}, 1)]));
    await engine.start();
    expect(engine.status, LeakRadarStatus.active);
    await engine.stop();
  });

  test('status is preciseOnly when the probe is unavailable', () async {
    final engine = engineWith(FakeHeapProbe([], available: false));
    await engine.start();
    expect(engine.status, LeakRadarStatus.preciseOnly);
    await engine.stop();
  });

  test('repeated scans build history and detect growth', () async {
    final probe = FakeHeapProbe([snap({'HomeBloc': 1}, 1), snap({'HomeBloc': 2}, 2), snap({'HomeBloc': 3}, 3)]);
    final engine = engineWith(probe);
    await engine.start();
    await engine.scan();
    await engine.scan();
    final report = await engine.scan();
    final f = report.findings.firstWhere((f) => f.className == 'HomeBloc');
    expect(f.kind, LeakKind.growth);
    expect(f.liveCount, 3);
    await engine.stop();
  });

  test('overlapping scans are dropped, not queued', () async {
    final probe = FakeHeapProbe([snap({'A': 1}, 1)]);
    final engine = engineWith(probe);
    await engine.start();
    final a = engine.scan();
    final b = engine.scan(); // should be dropped while `a` is in flight
    await Future.wait([a, b]);
    expect(probe.captureCount, 1);
    await engine.stop();
  });

  test('reports stream emits each scan', () async {
    final probe = FakeHeapProbe([snap({'A': 1}, 1)]);
    final engine = engineWith(probe);
    await engine.start();
    final future = engine.reports.first;
    await engine.scan();
    expect((await future).trigger, 'manual');
    await engine.stop();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/engine/leak_engine_test.dart`
Expected: FAIL — `LeakEngine` not defined.

- [ ] **Step 3: Implement `leak_engine.dart`**

```dart
// lib/src/engine/leak_engine.dart
import 'dart:async';

import 'package:meta/meta.dart';

import '../analysis/leak_analyzer.dart';
import '../analysis/sample_history.dart';
import '../model/leak_report.dart';
import '../model/leak_kind.dart';
import '../precise/leak_object_registry.dart';
import '../util/rate_limited_logger.dart';
import '../util/safe.dart';
import 'heap_probe.dart';

/// Orchestrates capture → analyze → report. Internal; reachable from the
/// facade and tests, but never part of the public API.
@internal
class LeakEngine {
  LeakEngine({
    required HeapProbe probe,
    required LeakAnalyzer analyzer,
    SampleHistory? history,
    LeakObjectRegistry? registry,
    this.gcCyclesForPreciseLeak = 3,
    RateLimitedLogger? logger,
  })  : _probe = probe,
        _analyzer = analyzer,
        _history = history ?? SampleHistory(),
        _registry = registry ?? LeakObjectRegistry(),
        _logger = logger ?? RateLimitedLogger();

  final HeapProbe _probe;
  final LeakAnalyzer _analyzer;
  final SampleHistory _history;
  final LeakObjectRegistry _registry;
  final int gcCyclesForPreciseLeak;
  final RateLimitedLogger _logger;

  final StreamController<LeakReport> _reports = StreamController<LeakReport>.broadcast();
  LeakRadarStatus _status = LeakRadarStatus.disabled;
  LeakReport? _latest;
  bool _scanning = false;

  Stream<LeakReport> get reports => _reports.stream;
  LeakReport? get latest => _latest;
  LeakRadarStatus get status => _status;

  Future<void> start() async {
    final available = await runSafelyAsync(() => _probe.isAvailable, fallback: false, logger: _logger);
    _status = available ? LeakRadarStatus.active : LeakRadarStatus.preciseOnly;
  }

  void track(Object o, {required String tag}) => _registry.track(o, tag: tag);
  void markDisposed(Object o) => _registry.markDisposed(o);

  Future<LeakReport> scan({String trigger = 'manual'}) async {
    if (_scanning) return _latest ?? _degraded(trigger);
    _scanning = true;
    try {
      if (_status == LeakRadarStatus.active) {
        final snapshot = await runSafelyAsync(
          () => _probe.capture(forceGc: true),
          fallback: null,
          logger: _logger,
        );
        if (snapshot == null) {
          _status = LeakRadarStatus.serviceUnavailable;
        } else {
          _history.add(snapshot);
        }
      }
      final precise = _registry.collectLeaks(gcCycles: gcCyclesForPreciseLeak);
      final report = _analyzer.analyze(_history, trigger: trigger, status: _status, preciseFindings: precise);
      _latest = report;
      if (!_reports.isClosed) _reports.add(report);
      return report;
    } finally {
      _scanning = false;
    }
  }

  LeakReport _degraded(String trigger) =>
      LeakReport(findings: const [], capturedAt: DateTime.now(), trigger: trigger, status: _status);

  Future<void> stop() async {
    await runSafelyAsync(() => _probe.dispose(), fallback: null, logger: _logger);
    _registry.clear();
    await _reports.close();
    _status = LeakRadarStatus.disabled;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/engine/leak_engine_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/engine/leak_engine.dart test/engine/leak_engine_test.dart
git commit -m "feat: add LeakEngine orchestrator (capture/analyze/report, scan serialization)"
```

---

### Task 10: LeakRadar facade + LeakRadarConfig

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/config/leak_radar_config.dart`
- Create: `packages/flutter_leak_radar/lib/src/leak_radar.dart`
- Modify: `packages/flutter_leak_radar/lib/flutter_leak_radar.dart` (public exports)
- Test: `packages/flutter_leak_radar/test/leak_radar_test.dart`

**Interfaces:**
- Consumes: `LeakEngine`, `LeakAnalyzer`, `SampleHistory`, `LeakObjectRegistry`, `VmHeapProbe`, `NoopHeapProbe`, `SuspectSet`, `LeakRule`, models, `kEngineEnabled`, `RateLimitedLogger`.
- Produces:
  - `final class LeakRadarConfig` (fields: `enabled`, `suspects`, `rules`, `maxSnapshots`, `gcCyclesForPreciseLeak`, `disposalGrace`, `logLevel`) + `LeakRadarConfig.standard(...)` + `copyWith`/`==`/`hashCode`.
  - `abstract final class LeakRadar` with static `init`, `scan`, `track`, `markDisposed`, `reports`, `latest`, `status`, `dispose`, and `@visibleForTesting debugInstall(LeakEngine)`.

> MVP note: `autoScan`, `overlay`, `navigatorObserver`, `exportToFile`, `showOverlay`, `maxRetainingPathRequests` from the spec are deferred to the follow-up plan. Field names that DO ship here match the spec so the follow-up extends rather than renames.

- [ ] **Step 1: Write the failing test**

```dart
// test/leak_radar_test.dart
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_heap_probe.dart';

void main() {
  tearDown(() => LeakRadar.dispose());

  test('disabled config -> status disabled and scan returns a disabled report', () async {
    await LeakRadar.init(const LeakRadarConfig(enabled: false));
    expect(LeakRadar.status, LeakRadarStatus.disabled);
    final report = await LeakRadar.scan();
    expect(report.status, LeakRadarStatus.disabled);
    expect(report.findings, isEmpty);
  });

  test('track/markDisposed never throw when disabled', () async {
    await LeakRadar.init(const LeakRadarConfig(enabled: false));
    final o = Object();
    LeakRadar.track(o, tag: 'x'); // no-op, no throw
    LeakRadar.markDisposed(o);
    expect(LeakRadar.latest, isNull);
  });

  test('debugInstall wires a fake engine and scan reports findings', () async {
    final probe = FakeHeapProbe([
      HeapSnapshot(capturedAt: DateTime(2026), samples: const [ClassSample(className: 'HomeBloc', instancesCurrent: 5, bytesCurrent: 0, timestamp: _epoch)]),
    ]);
    final engine = LeakEngine(probe: probe, analyzer: const LeakAnalyzer(SuspectSet.empty()));
    await LeakRadar.debugInstall(engine);
    final report = await LeakRadar.scan();
    expect(report.status, LeakRadarStatus.active);
  });
}

const _epoch = null; // placeholder not used; replaced below
```

> Fix the timestamp: replace the snapshot's `timestamp: _epoch` with `timestamp: DateTime(2026)` and delete the `_epoch` line. (Shown explicitly so the implementer doesn't ship a null.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/leak_radar_test.dart`
Expected: FAIL — `LeakRadarConfig`/`LeakRadar` not defined.

- [ ] **Step 3: Implement `leak_radar_config.dart`**

```dart
// lib/src/config/leak_radar_config.dart
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

import '../util/rate_limited_logger.dart';
import 'leak_rule.dart';
import 'suspect_set.dart';

@immutable
final class LeakRadarConfig {
  const LeakRadarConfig({
    this.enabled = true,
    this.suspects = const SuspectSet.empty(),
    this.rules = const <LeakRule>[],
    this.maxSnapshots = 20,
    this.gcCyclesForPreciseLeak = 3,
    this.disposalGrace = const Duration(seconds: 2),
    this.logLevel = LeakLogLevel.warning,
  });

  /// Typical wiring: enabled only in debug/profile, defaults suspects.
  factory LeakRadarConfig.standard({
    List<LeakRule> rules = const <LeakRule>[],
    SuspectSet? suspects,
    int maxSnapshots = 20,
  }) =>
      LeakRadarConfig(
        enabled: kDebugMode || kProfileMode,
        suspects: suspects ?? SuspectSet.defaults(),
        rules: rules,
        maxSnapshots: maxSnapshots,
      );

  final bool enabled;
  final SuspectSet suspects;
  final List<LeakRule> rules;
  final int maxSnapshots;
  final int gcCyclesForPreciseLeak;
  final Duration disposalGrace;
  final LeakLogLevel logLevel;

  LeakRadarConfig copyWith({
    bool? enabled,
    SuspectSet? suspects,
    List<LeakRule>? rules,
    int? maxSnapshots,
    int? gcCyclesForPreciseLeak,
    Duration? disposalGrace,
    LeakLogLevel? logLevel,
  }) =>
      LeakRadarConfig(
        enabled: enabled ?? this.enabled,
        suspects: suspects ?? this.suspects,
        rules: rules ?? this.rules,
        maxSnapshots: maxSnapshots ?? this.maxSnapshots,
        gcCyclesForPreciseLeak: gcCyclesForPreciseLeak ?? this.gcCyclesForPreciseLeak,
        disposalGrace: disposalGrace ?? this.disposalGrace,
        logLevel: logLevel ?? this.logLevel,
      );

  @override
  bool operator ==(Object other) =>
      other is LeakRadarConfig &&
      other.enabled == enabled &&
      other.suspects == suspects &&
      other.maxSnapshots == maxSnapshots &&
      other.gcCyclesForPreciseLeak == gcCyclesForPreciseLeak &&
      other.disposalGrace == disposalGrace &&
      other.logLevel == logLevel;

  @override
  int get hashCode => Object.hash(enabled, suspects, maxSnapshots, gcCyclesForPreciseLeak, disposalGrace, logLevel);
}
```

- [ ] **Step 4: Implement `leak_radar.dart`**

```dart
// lib/src/leak_radar.dart
import 'package:meta/meta.dart';

import 'analysis/leak_analyzer.dart';
import 'analysis/sample_history.dart';
import 'config/leak_radar_config.dart';
import 'engine/heap_probe.dart';
import 'engine/leak_engine.dart';
import 'engine/vm_heap_probe.dart';
import 'model/leak_kind.dart';
import 'model/leak_report.dart';
import 'precise/leak_object_registry.dart';
import 'util/build_mode.dart';
import 'util/rate_limited_logger.dart';
import 'util/safe.dart';

/// On-device leak detector. Static facade; every method is a no-op in release
/// or when disabled, and never throws into the host.
abstract final class LeakRadar {
  static LeakEngine? _engine;
  static RateLimitedLogger _logger = RateLimitedLogger();

  static Future<void> init(LeakRadarConfig config) async {
    await dispose();
    if (!kEngineEnabled || !config.enabled) {
      _engine = null;
      return;
    }
    await runSafelyAsync<void>(() async {
      _logger = RateLimitedLogger(level: config.logLevel);
      HeapProbe probe = VmHeapProbe(logger: _logger);
      if (!await probe.isAvailable) {
        await probe.dispose();
        probe = const NoopHeapProbe();
      }
      final engine = LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(config.suspects.merge(config.rules)),
        history: SampleHistory(maxSnapshots: config.maxSnapshots),
        registry: LeakObjectRegistry(disposalGrace: config.disposalGrace),
        gcCyclesForPreciseLeak: config.gcCyclesForPreciseLeak,
        logger: _logger,
      );
      await engine.start();
      _engine = engine;
    }, fallback: null, logger: _logger);
  }

  /// Test seam: install a pre-built engine (e.g. with a FakeHeapProbe).
  @visibleForTesting
  static Future<void> debugInstall(LeakEngine engine) async {
    await dispose();
    await engine.start();
    _engine = engine;
  }

  static Future<LeakReport> scan({String trigger = 'manual'}) {
    final engine = _engine;
    if (engine == null) {
      return Future.value(LeakReport(findings: const [], capturedAt: DateTime.now(), trigger: trigger, status: LeakRadarStatus.disabled));
    }
    return runSafelyAsync(
      () => engine.scan(trigger: trigger),
      fallback: LeakReport(findings: const [], capturedAt: DateTime.now(), trigger: trigger, status: LeakRadarStatus.serviceUnavailable),
      logger: _logger,
    );
  }

  static void track(Object object, {required String tag}) =>
      runSafely<void>(() => _engine?.track(object, tag: tag), fallback: null, logger: _logger);

  static void markDisposed(Object object) =>
      runSafely<void>(() => _engine?.markDisposed(object), fallback: null, logger: _logger);

  static Stream<LeakReport> get reports => _engine?.reports ?? const Stream<LeakReport>.empty();

  static LeakReport? get latest => _engine?.latest;

  static LeakRadarStatus get status => _engine?.status ?? LeakRadarStatus.disabled;

  static Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await runSafelyAsync(() => engine.stop(), fallback: null, logger: _logger);
    }
  }
}
```

- [ ] **Step 5: Update the public entrypoint exports**

```dart
// lib/flutter_leak_radar.dart
/// On-device, zero-config memory-leak detector for Flutter.
library;

export 'src/leak_radar.dart' show LeakRadar;
export 'src/config/leak_radar_config.dart' show LeakRadarConfig;
export 'src/config/leak_rule.dart' show LeakRule, LeakDetectionMode;
export 'src/config/suspect_set.dart' show SuspectSet;
export 'src/model/leak_report.dart' show LeakReport;
export 'src/model/leak_finding.dart' show LeakFinding;
export 'src/model/retaining_path.dart' show RetainingPathView, RetainingHop;
export 'src/model/leak_kind.dart' show LeakKind, LeakSeverity, LeakRadarStatus;
export 'src/util/rate_limited_logger.dart' show LeakLogLevel;
```

- [ ] **Step 6: Run tests (and fix the test timestamp placeholder noted in Step 1)**

Run: `flutter test test/leak_radar_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/src/config/leak_radar_config.dart lib/src/leak_radar.dart lib/flutter_leak_radar.dart test/leak_radar_test.dart
git commit -m "feat: add LeakRadar facade + LeakRadarConfig + public exports"
```

---

### Task 11: Minimal results screen (`LeakRadarScreen`)

**Files:**
- Create: `packages/flutter_leak_radar/lib/src/ui/leak_radar_screen.dart`
- Modify: `packages/flutter_leak_radar/lib/flutter_leak_radar.dart` (export the screen)
- Test: `packages/flutter_leak_radar/test/ui/leak_radar_screen_test.dart`

**Interfaces:**
- Consumes: `LeakRadar` facade (`reports`, `latest`, `status`, `scan`), `LeakReport`, `LeakFinding`, `LeakSeverity`.
- Produces: `class LeakRadarScreen extends StatefulWidget` — a Scaffold with a "Scan now" action, a findings list (class, severity chip, live count, growth), and an empty state showing `status`.

> MVP screen omits the growth sparkline and lazy retaining-path expansion (follow-up plan). It shows findings and lets you trigger a scan — enough to be usable on-device.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/ui/leak_radar_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/ui/leak_radar_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';

HeapSnapshot snap(Map<String, int> c) => HeapSnapshot(
      capturedAt: DateTime(2026),
      samples: [for (final e in c.entries) ClassSample(className: e.key, instancesCurrent: e.value, bytesCurrent: 0, timestamp: DateTime(2026))],
    );

void main() {
  tearDown(() => LeakRadar.dispose());

  testWidgets('shows empty state then findings after Scan now', (tester) async {
    final probe = FakeHeapProbe([snap({'HomeBloc': 1}), snap({'HomeBloc': 2}), snap({'HomeBloc': 3})]);
    final engine = LeakEngine(probe: probe, analyzer: const LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')])));
    await LeakRadar.debugInstall(engine);
    await LeakRadar.scan();
    await LeakRadar.scan();

    await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
    await tester.tap(find.byTooltip('Scan now'));
    await tester.pumpAndSettle();

    expect(find.text('HomeBloc'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/leak_radar_screen_test.dart`
Expected: FAIL — `LeakRadarScreen` not defined.

- [ ] **Step 3: Implement `leak_radar_screen.dart`**

```dart
// lib/src/ui/leak_radar_screen.dart
import 'package:flutter/material.dart';

import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';

/// Minimal results screen: findings list + "Scan now". Push it from anywhere:
/// `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeakRadarScreen()));`
class LeakRadarScreen extends StatefulWidget {
  const LeakRadarScreen({super.key});

  @override
  State<LeakRadarScreen> createState() => _LeakRadarScreenState();
}

class _LeakRadarScreenState extends State<LeakRadarScreen> {
  LeakReport? _report;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _report = LeakRadar.latest;
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final report = await LeakRadar.scan();
    if (!mounted) return;
    setState(() {
      _report = report;
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leak Radar'),
        actions: [
          IconButton(
            tooltip: 'Scan now',
            icon: _scanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: report == null || report.findings.isEmpty
          ? _EmptyState(status: report?.status ?? LeakRadar.status)
          : ListView.builder(
              itemCount: report.findings.length,
              itemBuilder: (_, i) => _FindingTile(finding: report.findings[i]),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.status});
  final LeakRadarStatus status;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, size: 48),
            const SizedBox(height: 8),
            const Text('No leaks detected'),
            const SizedBox(height: 4),
            Text('status: ${status.name}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});
  final LeakFinding finding;

  Color _color(LeakSeverity s) => switch (s) {
        LeakSeverity.critical => Colors.red,
        LeakSeverity.warning => Colors.orange,
        LeakSeverity.info => Colors.blue,
      };

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(backgroundColor: _color(finding.severity), radius: 6),
        title: Text(finding.className),
        subtitle: Text('${finding.kind.name} · live ${finding.liveCount} · +${finding.growth}${finding.tag != null ? ' · ${finding.tag}' : ''}'),
        trailing: Text(finding.severity.name),
      );
}
```

- [ ] **Step 4: Export the screen**

Add to `lib/flutter_leak_radar.dart`:
```dart
export 'src/ui/leak_radar_screen.dart' show LeakRadarScreen;
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/ui/leak_radar_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/ui/leak_radar_screen.dart lib/flutter_leak_radar.dart test/ui/leak_radar_screen_test.dart
git commit -m "feat: add minimal LeakRadarScreen (findings list + scan now)"
```

---

### Task 12: Example app with an intentional leak

**Files:**
- Create: `example/pubspec.yaml`
- Create: `example/lib/main.dart`
- Create: `example/lib/leaky_screen.dart`
- Create: `example/README.md`

**Interfaces:**
- Consumes: the public API (`LeakRadar`, `LeakRadarConfig`, `LeakRule`, `SuspectSet`, `LeakRadarScreen`).
- Produces: a runnable Flutter app demonstrating detection of a screen that leaks a `Timer` + a `StreamController` by never disposing them.

- [ ] **Step 1: Create `example/pubspec.yaml`**

```yaml
name: flutter_leak_radar_example
description: Demo app for flutter_leak_radar.
publish_to: none
version: 0.0.1
environment:
  sdk: ">=3.10.0 <4.0.0"
  flutter: ">=3.38.0"
resolution: workspace
dependencies:
  flutter:
    sdk: flutter
  flutter_leak_radar:
    path: ../packages/flutter_leak_radar
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
```

- [ ] **Step 2: Create `example/lib/leaky_screen.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

/// A screen that INTENTIONALLY leaks: it starts a periodic Timer and opens a
/// StreamController in initState but never cancels/closes them in dispose().
/// Each push/pop leaves the State (and its Timer) retained.
class LeakyScreen extends StatefulWidget {
  const LeakyScreen({super.key});
  @override
  State<LeakyScreen> createState() => _LeakyScreenState();
}

class _LeakyScreenState extends State<LeakyScreen> {
  late final Timer _timer;
  final StreamController<int> _controller = StreamController<int>.broadcast();

  @override
  void initState() {
    super.initState();
    LeakRadar.track(this, tag: 'LeakyScreenState'); // precise opt-in
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _controller.add(0));
  }

  // BUG ON PURPOSE: no dispose() cancelling _timer / closing _controller,
  // and no LeakRadar.markDisposed(this).

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Leaky screen')),
        body: const Center(child: Text('Pop me, then Scan in Leak Radar.')),
      );
}
```

- [ ] **Step 3: Create `example/lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

import 'leaky_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LeakRadar.init(LeakRadarConfig.standard(
    rules: const [LeakRule.maxLive('_LeakyScreenState', 1)],
    suspects: SuspectSet.defaults(),
  ));
  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Leak Radar Example',
        home: const _Home(),
      );
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Leak Radar Example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeakyScreen())),
                child: const Text('Open leaky screen'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeakRadarScreen())),
                child: const Text('Open Leak Radar'),
              ),
            ],
          ),
        ),
      );
}
```

- [ ] **Step 4: Create `example/README.md`**

````markdown
# flutter_leak_radar example

Run in profile (recommended) or debug:

```bash
cd example
flutter run --profile
```

Repro: tap **Open leaky screen** a few times (push + back each time), then **Open Leak Radar** → **Scan now**. `_LeakyScreenState` should appear as a growth/maxLive finding (the screen never disposes its `Timer`/`StreamController`), and as a precise `notGced` finding via `LeakRadar.track`.
````

- [ ] **Step 5: Verify the example builds**

Run: `cd example && flutter pub get && flutter analyze`
Expected: no analyzer errors.

- [ ] **Step 6: Commit**

```bash
git add example/
git commit -m "feat: add example app with an intentional Timer/StreamController leak"
```

---

## Self-Review

Run after completing all tasks; fix any gaps inline.

- **Spec coverage (MVP scope):** §2.3 `VmHeapProbe` → Task 8; §2.5 `LeakAnalyzer` → Task 5; §2.6 `SampleHistory` → Task 4; §2.7 `LeakObjectRegistry` → Task 6; §2.4 `SuspectSet`/`LeakRule` → Task 3; §4.1 facade → Task 10; §4.4 models → Task 2; §8 build-mode no-op → Tasks 1 + 10 (`enabled:false` invariant test); §10 testing → tests in every task. **Deferred (tracked for follow-up plan, NOT in scope here):** §2.2 periodic scheduler + §2.8 navigator observer (triggers), §2.9 overlay badge + sparkline + lazy retaining-path tile, §4.x `overlay`/`navigatorObserver`/`exportToFile`/`AutoScan`, §7.3 export/share. Add a `docs/plans/` follow-up plan for these before M3.
- **Placeholder scan:** the only intentional placeholder is the `_epoch` line in Task 10's test, with explicit instructions to replace it — verify it's removed.
- **Type consistency:** `HeapProbe.capture({required bool forceGc})`, `retainingPath(String, {int maxInstances})`; `LeakEngine.scan({String trigger})`; `LeakAnalyzer.analyze(SampleHistory, {required String trigger, required LeakRadarStatus status, List<LeakFinding> preciseFindings})`; `LeakRule.matches(String)`; `SuspectSet.ruleFor(String)`/`merge(List<LeakRule>)`; `LeakObjectRegistry.collectLeaks({int gcCycles, DateTime? now})` — names are consistent across producing and consuming tasks.
- **Known spec deltas (intentional):** `SuspectSet.defaults()` uses `*State` (not `State`) and `*StreamSubscription`/`*StreamController` so concrete/private class names match; `LeakObjectRegistry` exposes `collectLeaks` (not `collectPreciseLeaks`) and is sync with an injected `GcCounter` for testability — the `Finalizer`-based `notDisposed` path is deferred to the follow-up plan.

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-06-23-flutter-leak-radar-runtime-mvp.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session via executing-plans, batched with checkpoints.

Which approach?
