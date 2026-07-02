# Radar Native v1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build the device-independent foundation of the Native leak lane — a new pure-Dart `radar_native` package with the Lane B (heapprofd) data models, the still-live allocation-diff analysis, a `MemorySession` multi-modal container, and the `.pftrace`-parser *interface* (with a test double). This closes the review's #1 blocking gap (no concrete data model) and delivers the recommended-v1 core analysis — all buildable and fully unit-tested **without a device**.

**Design source:** `docs/specs/2026-07-02-native-gpu-leak-analysis-design.md` (with folded corrections) and its review `docs/specs/2026-07-02-native-gpu-review.md`. This plan implements the review's **"smallest useful v1 = Lane B only"** recommendation, minus the device-gated capture pipeline.

**Architecture:** `radar_native` is a pure-Dart, publishable package (a peer to `leak_graph`, NOT a Flutter package). It has zero device/plugin dependencies. Lane B's "what is a leak with no GC roots" is answered by **alloc−free still-live accounting across ≥2 heapprofd checkpoints, ranked by bytes + growth** — a pure function over the models, tested with synthetic data. The real `.pftrace → NativeHeapProfile` parser (Perfetto `trace_processor` over a bundled binary + `package:sqlite3`) is a **device/binary-dependent seam**: this plan defines its interface + an in-memory test double, and defers the concrete implementation to the post-spike phase.

## Explicitly OUT of scope (device/spike-gated — Ivan runs the spikes first)
Per the review, three spikes must pass on a real device before the capture pipeline is built: (1) `.pftrace` round-trip on a profileable KATIM build; (2) the Lane C `Texture`-hook reality-check; (3) the standalone ffi wrapper. This plan builds **none** of: the concrete Perfetto trace-processor parser, on-device capture (adb/`Process`), the desktop screens/rail integration, or Lanes A/C/D. Those are the next phase, unblocked once the spikes pass.

## Global Constraints

- SDK floor `>=3.10.0 <4.0.0`. `radar_native` is **pure Dart** (`dart test`, not `flutter test`) — deps limited to `meta` (like `leak_graph`); NO Flutter, NO `dart:io` in `lib/` (parsing bytes is host-agnostic; file reading is the host's job), NO device/plugin imports.
- Strict analysis: `dart analyze --fatal-infos` clean. Mirror `leak_graph`'s `analysis_options.yaml`.
- Format: `dart format --set-exit-if-changed .` — run `dart format .` before every commit.
- Models follow `leak_graph`'s conventions: `final class`, `const` constructors, `toJson()`/`factory fromJson()`, value equality (`==`/`hashCode`) where used as map/set keys, and a `version` field on top-level serializable envelopes (`NativeHeapProfile`, `MemorySession`) exactly as `PersistedSession` carries `'version': 1`.
- The still-live convention mirrors `computeDiff`'s zero-baseline: a callsite absent from `before` reads as 0 there (not dropped).
- `radar_native` version `0.1.0`. Publishable (`publish_to` omitted, like `leak_graph`) so it can ship independently; add to the root `pubspec.yaml` workspace list + resolves via `resolution: workspace`.
- Commit after every task. `melos` via `dart run melos`.

---

## File Structure

```
packages/radar_native/pubspec.yaml
packages/radar_native/analysis_options.yaml
packages/radar_native/lib/radar_native.dart                 # barrel
packages/radar_native/lib/src/model/native_frame.dart       # NativeFrame
packages/radar_native/lib/src/model/native_callsite.dart    # NativeCallsite
packages/radar_native/lib/src/model/native_heap_profile.dart# NativeHeapProfile (one heapprofd checkpoint)
packages/radar_native/lib/src/model/native_allocation_diff.dart # per-callsite delta
packages/radar_native/lib/src/model/memory_session.dart     # multi-modal container
packages/radar_native/lib/src/analysis/native_diff.dart     # diffNativeProfiles + ranking
packages/radar_native/lib/src/parse/native_profile_parser.dart # interface + InMemoryNativeProfileParser (test double)
packages/radar_native/test/…
pubspec.yaml (root)                                          # + packages/radar_native
```

---

## Task 1: Scaffold `radar_native` package

**Files:** create `packages/radar_native/pubspec.yaml`, `analysis_options.yaml`, `lib/radar_native.dart`, `test/scaffold_test.dart`; modify root `pubspec.yaml`.

- [ ] **Step 1: pubspec** — `packages/radar_native/pubspec.yaml`:
```yaml
name: radar_native
description: >-
  Pure-Dart models and analysis for native-heap (heapprofd/Perfetto) leak
  detection — a peer to leak_graph for the native memory lane.
version: 0.1.0
repository: https://github.com/tp9imka/flutter-leak-radar

environment:
  sdk: ">=3.10.0 <4.0.0"

resolution: workspace

dependencies:
  meta: ^1.15.0

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
```

- [ ] **Step 2: analysis_options** — mirror `packages/leak_graph/analysis_options.yaml` (read it and copy). If it just includes `package:lints/recommended.yaml` + strict language modes, replicate exactly.

- [ ] **Step 3: barrel** — `packages/radar_native/lib/radar_native.dart`:
```dart
/// Pure-Dart native-heap leak analysis (Lane B: heapprofd still-live accounting).
///
/// Models + analysis for the native memory lane, a peer to `leak_graph`.
/// Exports are added incrementally as each model/analysis lands.
library;
```

- [ ] **Step 4: workspace wiring** — add `- packages/radar_native` to the root `pubspec.yaml` `workspace:` list (after `packages/radar_workbench`).

- [ ] **Step 5: scaffold test** — `packages/radar_native/test/scaffold_test.dart`:
```dart
import 'package:test/test.dart';

void main() {
  test('radar_native resolves', () => expect(1 + 1, 2));
}
```

- [ ] **Step 6: resolve + test** — Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart pub get` (expect resolves). Then `cd packages/radar_native && dart test` (PASS) and `dart analyze --fatal-infos .` (clean).

- [ ] **Step 7: commit** — `dart format .`; `git add packages/radar_native pubspec.yaml && git commit -m "feat(radar_native): scaffold pure-Dart native-heap analysis package"`.

---

## Task 2: `NativeFrame` + `NativeCallsite` models

Faithful to Perfetto's `stack_profile_frame`/`stack_profile_mapping` (a frame = function name + owning module/build-id) and `heap_profile_allocation` aggregated per callsite (alloc/free bytes+counts → still-live).

**Files:** create `lib/src/model/native_frame.dart`, `lib/src/model/native_callsite.dart`, `test/native_callsite_test.dart`; modify barrel.

**Interfaces produced:**
- `final class NativeFrame { final String function; final String module; final String? buildId; }` — `toJson`/`fromJson`, value equality.
- `final class NativeCallsite { final List<NativeFrame> frames; final int allocBytes; final int allocCount; final int freeBytes; final int freeCount; int get stillLiveBytes => allocBytes - freeBytes; int get stillLiveCount => allocCount - freeCount; String get signature; }` — `signature` = a stable join of `module>function` over `frames` (leaf-first, last-N), the callsite identity used for cross-checkpoint diffing. `toJson`/`fromJson`.

- [ ] **Step 1: failing test** — `test/native_callsite_test.dart`:
```dart
import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

void main() {
  NativeCallsite cs(String fn, {int alloc = 0, int free = 0, int aC = 0, int fC = 0}) =>
      NativeCallsite(
        frames: [NativeFrame(function: fn, module: 'libfoo.so', buildId: 'abc')],
        allocBytes: alloc, allocCount: aC, freeBytes: free, freeCount: fC,
      );

  test('stillLive = alloc - free', () {
    final c = cs('leaky', alloc: 1000, free: 200, aC: 10, fC: 2);
    expect(c.stillLiveBytes, 800);
    expect(c.stillLiveCount, 8);
  });

  test('signature is stable + identifies the callsite', () {
    expect(cs('a').signature, cs('a').signature);
    expect(cs('a').signature, isNot(cs('b').signature));
  });

  test('NativeCallsite JSON round-trips', () {
    final c = cs('leaky', alloc: 1000, free: 200, aC: 10, fC: 2);
    final back = NativeCallsite.fromJson(c.toJson());
    expect(back.stillLiveBytes, 800);
    expect(back.frames.single.function, 'leaky');
    expect(back.frames.single.module, 'libfoo.so');
  });

  test('NativeFrame value equality', () {
    expect(
      const NativeFrame(function: 'f', module: 'm', buildId: 'b'),
      const NativeFrame(function: 'f', module: 'm', buildId: 'b'),
    );
  });
}
```

- [ ] **Step 2: run → FAIL** (`cd packages/radar_native && dart test test/native_callsite_test.dart`).

- [ ] **Step 3: implement `native_frame.dart`:**
```dart
import 'package:meta/meta.dart';

/// One resolved stack frame: a native function in an owning module
/// (Perfetto `stack_profile_frame` + `stack_profile_mapping`).
@immutable
final class NativeFrame {
  const NativeFrame({
    required this.function,
    required this.module,
    this.buildId,
  });

  /// Symbolized function name (or a `0x…` address when unsymbolized).
  final String function;

  /// Owning module (mapping name, e.g. `libflutter.so`).
  final String module;

  /// Build-id of [module], for symbol-store lookup (nullable if unknown).
  final String? buildId;

  Map<String, Object?> toJson() => {
        'function': function,
        'module': module,
        if (buildId != null) 'buildId': buildId,
      };

  factory NativeFrame.fromJson(Map<String, Object?> json) => NativeFrame(
        function: json['function'] as String,
        module: json['module'] as String,
        buildId: json['buildId'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is NativeFrame &&
      other.function == function &&
      other.module == module &&
      other.buildId == buildId;

  @override
  int get hashCode => Object.hash(function, module, buildId);
}
```

- [ ] **Step 4: implement `native_callsite.dart`:**
```dart
import 'package:meta/meta.dart';

import 'native_frame.dart';

/// A leaf callsite with its stack and aggregated allocation accounting from a
/// single heapprofd checkpoint. Still-live = alloc − free is the Lane B leak
/// signal (no GC: what was allocated and never freed).
@immutable
final class NativeCallsite {
  const NativeCallsite({
    required this.frames,
    required this.allocBytes,
    required this.allocCount,
    required this.freeBytes,
    required this.freeCount,
  });

  /// Stack for this callsite, leaf-first (index 0 = the allocating frame).
  final List<NativeFrame> frames;

  final int allocBytes;
  final int allocCount;
  final int freeBytes;
  final int freeCount;

  /// Bytes allocated here and not yet freed — the leak signal.
  int get stillLiveBytes => allocBytes - freeBytes;

  /// Allocations here not yet freed.
  int get stillLiveCount => allocCount - freeCount;

  /// Stable identity for cross-checkpoint diffing: `module>function` over the
  /// (leaf-first) frames. Two checkpoints' callsites with the same signature
  /// are "the same site".
  String get signature =>
      frames.map((f) => '${f.module}>${f.function}').join('|');

  Map<String, Object?> toJson() => {
        'frames': [for (final f in frames) f.toJson()],
        'allocBytes': allocBytes,
        'allocCount': allocCount,
        'freeBytes': freeBytes,
        'freeCount': freeCount,
      };

  factory NativeCallsite.fromJson(Map<String, Object?> json) => NativeCallsite(
        frames: [
          for (final e in (json['frames'] as List? ?? const []))
            NativeFrame.fromJson((e as Map).cast<String, Object?>()),
        ],
        allocBytes: (json['allocBytes'] as num).toInt(),
        allocCount: (json['allocCount'] as num).toInt(),
        freeBytes: (json['freeBytes'] as num).toInt(),
        freeCount: (json['freeCount'] as num).toInt(),
      );
}
```

- [ ] **Step 5: export** both from the barrel:
```dart
export 'src/model/native_callsite.dart';
export 'src/model/native_frame.dart';
```

- [ ] **Step 6: run → PASS**; **Step 7:** analyze clean, format, commit `feat(radar_native): NativeFrame + NativeCallsite models`.

---

## Task 3: `NativeHeapProfile` (one checkpoint)

**Files:** create `lib/src/model/native_heap_profile.dart`, `test/native_heap_profile_test.dart`; modify barrel.

**Interfaces produced:**
- `final class NativeHeapProfile { final DateTime capturedAt; final String label; final List<NativeCallsite> callsites; final NativeProfileMeta meta; int get totalStillLiveBytes; }` + `NativeProfileMeta { final int? pid; final String? package; final int? samplingIntervalBytes; }`. Envelope carries `'version': 1`. `toJson`/`fromJson`.

- [ ] **Step 1: failing test** — round-trip a profile with 2 callsites; assert `totalStillLiveBytes` = sum of callsite still-live; assert `version` in JSON; assert `fromJson(toJson())` preserves callsites + meta.

- [ ] **Step 2: run → FAIL.**

- [ ] **Step 3: implement** `native_heap_profile.dart` — `final class NativeProfileMeta` (pid/package/samplingIntervalBytes, toJson/fromJson) + `final class NativeHeapProfile` with `totalStillLiveBytes => callsites.fold(0, (s, c) => s + c.stillLiveBytes)`, `toJson` writing `{'version': 1, 'capturedAt': iso, 'label', 'meta', 'callsites': [...]}`, and `fromJson` tolerant of a missing/older `version` (default the fields).

- [ ] **Step 4: export; Step 5: PASS; Step 6: analyze/format/commit** `feat(radar_native): NativeHeapProfile checkpoint model`.

---

## Task 4: `NativeAllocationDiff` + `diffNativeProfiles` (the Lane B core analysis)

The heart of the recommended v1: rank what grew in still-live bytes between two checkpoints. Pure function, synthetic-tested.

**Files:** create `lib/src/model/native_allocation_diff.dart`, `lib/src/analysis/native_diff.dart`, `test/native_diff_test.dart`; modify barrel.

**Interfaces produced:**
- `final class NativeAllocationDiff { final String signature; final List<NativeFrame> frames; final int beforeStillLiveBytes; final int afterStillLiveBytes; int get growthBytes; final int beforeStillLiveCount; final int afterStillLiveCount; int get growthCount; }`.
- `List<NativeAllocationDiff> diffNativeProfiles(NativeHeapProfile before, NativeHeapProfile after)` — join callsites by `signature`, a callsite absent from `before` reads as a zero baseline (matching `computeDiff`), sorted by `growthBytes` descending. (Callsites only in `before` and gone from `after` are dropped, matching `computeDiff`.)

- [ ] **Step 1: failing test** — `test/native_diff_test.dart`:
```dart
import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeCallsite _cs(String fn, {required int live, int count = 1}) => NativeCallsite(
      frames: [NativeFrame(function: fn, module: 'libx.so')],
      allocBytes: live, allocCount: count, freeBytes: 0, freeCount: 0,
    );

NativeHeapProfile _p(DateTime at, List<NativeCallsite> cs) =>
    NativeHeapProfile(capturedAt: at, label: at.toIso8601String(), callsites: cs,
        meta: const NativeProfileMeta());

void main() {
  final t0 = DateTime(2026, 1, 1, 9);
  final t1 = DateTime(2026, 1, 1, 13);

  test('ranks callsites by still-live growth, largest first', () {
    final before = _p(t0, [_cs('slow', live: 100), _cs('flat', live: 500)]);
    final after = _p(t1, [_cs('slow', live: 900), _cs('flat', live: 500)]);
    final diff = diffNativeProfiles(before, after);
    expect(diff.first.signature, _cs('slow', live: 0).signature); // grew 800
    expect(diff.first.growthBytes, 800);
    // 'flat' present with 0 growth, ordered after 'slow'.
    expect(diff.map((d) => d.growthBytes), [800, 0]);
  });

  test('a callsite new in after reads against a zero baseline', () {
    final before = _p(t0, [_cs('old', live: 100)]);
    final after = _p(t1, [_cs('old', live: 100), _cs('brandnew', live: 300)]);
    final diff = diffNativeProfiles(before, after);
    final n = diff.firstWhere((d) => d.frames.single.function == 'brandnew');
    expect(n.beforeStillLiveBytes, 0);
    expect(n.growthBytes, 300);
  });
}
```

- [ ] **Step 2: run → FAIL.**

- [ ] **Step 3: implement** `native_allocation_diff.dart` (the model, toJson/fromJson) + `native_diff.dart`:
```dart
import '../model/native_allocation_diff.dart';
import '../model/native_heap_profile.dart';

/// Ranks what grew in still-live bytes between two heapprofd checkpoints —
/// the Lane B leak signal (no GC roots; growth in never-freed bytes). Joins
/// callsites by [NativeCallsite.signature]; a site absent from [before] reads
/// as a zero baseline (matching leak_graph's computeDiff). Sorted by growth
/// bytes, descending.
List<NativeAllocationDiff> diffNativeProfiles(
  NativeHeapProfile before,
  NativeHeapProfile after,
) {
  final beforeBySig = {for (final c in before.callsites) c.signature: c};
  final diffs = <NativeAllocationDiff>[
    for (final a in after.callsites)
      () {
        final b = beforeBySig[a.signature];
        return NativeAllocationDiff(
          signature: a.signature,
          frames: a.frames,
          beforeStillLiveBytes: b?.stillLiveBytes ?? 0,
          afterStillLiveBytes: a.stillLiveBytes,
          beforeStillLiveCount: b?.stillLiveCount ?? 0,
          afterStillLiveCount: a.stillLiveCount,
        );
      }(),
  ]..sort((x, y) => y.growthBytes.compareTo(x.growthBytes));
  return diffs;
}
```
(`NativeAllocationDiff.growthBytes => afterStillLiveBytes - beforeStillLiveBytes`; `growthCount` similarly.)

- [ ] **Step 4: export both; Step 5: PASS; Step 6: analyze/format/commit** `feat(radar_native): NativeAllocationDiff + diffNativeProfiles (Lane B still-live diff)`.

---

## Task 5: `MemorySession` multi-modal container

The peer-to-`SnapshotBundle` container the review calls for: time-aligns native profiles with (references to) Dart-heap analyses. v1 holds native profiles + opaque Dart-analysis references (by id/label) — no `leak_graph` dependency; the desktop correlates later.

**Files:** create `lib/src/model/memory_session.dart`, `test/memory_session_test.dart`; modify barrel.

**Interfaces produced:**
- `final class DartAnalysisRef { final int bundleId; final String label; final DateTime capturedAt; }` — an opaque pointer to a `.dartheap` analysis held elsewhere (the desktop's `SnapshotBundle`).
- `final class MemorySession { final String label; final List<NativeHeapProfile> nativeProfiles; final List<DartAnalysisRef> dartRefs; }` — envelope with `'version': 1`, `toJson`/`fromJson`. A `List<({DateTime at, String kind, String label})> get timeline` sorted by `capturedAt` unifying both lanes on one axis (the review's "one shared axis"; kind ∈ {native, dart}).

- [ ] **Step 1: failing test** — build a session with 2 native profiles + 1 dart ref; assert `timeline` is sorted by time and tags each entry's `kind`; assert JSON round-trip preserves both lists + `version`.
- [ ] **Step 2: FAIL. Step 3: implement.** Note (from the review, gap I4): document on `timeline` that callers must normalize clock domains before relying on ordering across lanes — for v1 this simply orders by the stored `capturedAt`, which the parser layer is responsible for populating in one clock. Add that as a doc comment.
- [ ] **Step 4: export; Step 5: PASS; Step 6: analyze/format/commit** `feat(radar_native): MemorySession multi-modal container`.

---

## Task 6: `NativeProfileParser` interface + test double; barrel + gate

The `.pftrace → NativeHeapProfile` seam. The concrete Perfetto-`trace_processor` parser is **device/binary-dependent (spike-gated)** and is NOT implemented here — only the interface + an in-memory double so downstream code can be written and tested now.

**Files:** create `lib/src/parse/native_profile_parser.dart`, `test/native_profile_parser_test.dart`; finalize barrel.

**Interfaces produced:**
- `abstract interface class NativeProfileParser { NativeHeapProfile parse(Object source, {String label}); }` — `source` is an opaque handle (a query result / rows) the host provides; kept `Object` so `radar_native` stays free of `sqlite3`/`dart:io`.
- `final class InMemoryNativeProfileParser implements NativeProfileParser` — takes a pre-built `NativeHeapProfile` (or a `List<NativeCallsite>` + meta) and returns it; the test/desktop-synthetic double.

- [ ] **Step 1: failing test** — `InMemoryNativeProfileParser(profile).parse(...)` returns the profile.
- [ ] **Step 2: FAIL. Step 3: implement** the interface + `InMemoryNativeProfileParser`, with a class-level doc block stating: "The concrete `PerfettoTraceProcessorParser` (bundled `trace_processor_shell` + `package:sqlite3`, querying `heap_profile_allocation`/`stack_profile_*`) lives in the host/desktop package and is gated on the `.pftrace` round-trip spike — see docs/specs/2026-07-02-native-gpu-review.md §5."
- [ ] **Step 4: finalize barrel** (export the parser). **Step 5: PASS.**
- [ ] **Step 6: gate** — `cd packages/radar_native && dart analyze --fatal-infos . && dart test` (all green); confirm the package is pure Dart (`! rg -n "package:flutter|dart:io|dart:ui" packages/radar_native/lib` → no matches). Format; commit `feat(radar_native): NativeProfileParser seam + test double; v1 foundation complete`.

---

## Self-Review Notes (for the executor)

- **Device-independent by construction.** Everything here is pure-Dart models + a pure diff function + an interface — no `.pftrace` parsing, no adb, no Flutter. It's fully unit-testable and is the review's recommended-v1 *analysis core*.
- **The one hard seam is deferred, not faked.** `NativeProfileParser` is an interface + an in-memory double; the real Perfetto/`sqlite3` parser is the spike-gated next step and does NOT belong in this pure package (it needs `dart:io`/binaries → the host/desktop package).
- **Faithful to Perfetto's stable schema** (`heap_profile_allocation`, `stack_profile_frame`/`mapping`) — the models won't need rework when the parser lands; they mirror what `trace_processor` actually returns.
- **Aligned with the review's corrections:** Lane B only (the anchor); no Lane D pointer-JOIN (impossible), no Lane C `Texture` model (unverified — its spike gates it). Still-live-diff is the honest "what is a leak" answer for the no-GC lane.
- **Next phase (post-spike, Ivan's device):** the concrete `PerfettoTraceProcessorParser` + on-device capture + the desktop screens/rail integration + Lanes A/C (once their spikes pass). This foundation is what those build on.
